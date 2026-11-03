#include "RadioController.h"
#include <QCryptographicHash>
#include <QJsonDocument>
#include <QPointer>
#include <algorithm>

namespace {
bool song(const QJsonObject &track) {
    return track["kind"] == "song" && !track["id"].toString().isEmpty() &&
           QStringList{"qq", "netease"}.contains(track["provider"].toString());
}
}

RadioController::RadioController(Host *host, MusicPlayer *player, QObject *parent)
    : QObject(parent), m_host(host), m_player(player), m_api(host) {
    m_api.provider = "qq";
    m_clock.start();
}

QByteArray RadioController::credential() const {
    // Compare locally only. Credentials and their hashes never enter snapshots/logs.
    const QJsonObject scope = m_api.provider == "qq"
        ? QJsonObject{{"session", m_host->cookies["qqmusic_session"]}, {"accounts", m_host->cookies["__qqSessions"]}}
        : QJsonObject{{"session", m_host->cookies["MUSIC_U"]}};
    return QCryptographicHash::hash(QJsonDocument(scope).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256);
}

int RadioController::upcoming() const {
    return std::max(0, int(m_player->queue.size()) - m_player->index - 1);
}

void RadioController::remember(const QJsonObject &track) {
    const auto key = MusicPlayer::identity(track);
    if (m_seen.contains(key)) return;
    m_recent.enqueue(key); m_seen.insert(key);
    while (m_recent.size() > 120) m_seen.remove(m_recent.dequeue());
}

void RadioController::start(const QString &provider, const QJsonObject &seed) {
    stop();
    if (!QStringList{"qq", "netease"}.contains(provider)) return;
    m_api.provider = provider;
    if (!m_host->offline && !m_host->hasCredential(provider)) {
        m_error = QStringLiteral("请先登录") + MusicApi::providerName(provider) + QStringLiteral("，再开启电台"); return;
    }
    if (!seed.isEmpty() && (!song(seed) || seed["provider"] != provider)) {
        m_error = QStringLiteral("请选择当前平台的推荐歌曲"); return;
    }
    m_active = true; m_credential = credential(); m_nextFetch = 0;
    m_batches = m_emptyBatches = m_failedTracks = 0; m_failedKey.clear();
    for (const auto &value : m_player->queue) remember(value.toObject());
    if (!seed.isEmpty()) startTrack(seed);
    else { m_startPending = true; fetch(); }
}

void RadioController::stop(const QString &reason) {
    ++m_generation; ++m_request;
    m_active = m_busy = m_waiting = m_startPending = m_paused = false;
    m_error = reason; m_generated.clear(); m_recent.clear(); m_seen.clear();
}

void RadioController::startTrack(const QJsonObject &track) {
    m_startPending = false;
    remember(track); m_generated.insert(MusicPlayer::identity(track));
    if (MusicPlayer::identity(track) == MusicPlayer::identity(m_player->current)) {
        m_player->setPaused(m_paused);
    } else {
        // Start here, but keep the user's already queued songs after it.
        m_player->enqueue(track, true);
        m_player->playIndex(m_player->index + 1);
        if (m_paused) m_player->setPaused(true);
    }
}

void RadioController::retry() {
    if (!m_active || m_busy) return;
    if (m_clock.elapsed() < m_nextFetch) return;
    m_error.clear(); m_emptyBatches = 0; m_failedTracks = 0;
    if (m_player->failed && upcoming() > 0) advance(1);
    else if (m_player->failed) m_waiting = true;
    fetch();
}

void RadioController::fetch() {
    if (!m_active || m_busy || !m_error.isEmpty() || m_clock.elapsed() < m_nextFetch) return;
    m_busy = true; m_requestClock.restart();
    const auto generation = m_generation, request = ++m_request;
    const auto epoch = m_host->epoch;
    m_api.call("discover", {"guess", m_batches * 5, QStringLiteral("全部")},
        [this, generation, request, epoch](MusicReply result) {
            if (!m_active || generation != m_generation || request != m_request) return;
            m_busy = false;
            if (credential() != m_credential) { stop(QStringLiteral("电台账号已变更，请重新开启")); return; }
            // A logout on the other platform invalidates Host requests as well.
            if (epoch != m_host->epoch) { m_nextFetch = m_clock.elapsed() + 1500; return; }
            m_nextFetch = m_clock.elapsed() + 1800;
            if (!result.ok()) {
                m_error = result.error.left(240);
                m_nextFetch = m_clock.elapsed() + std::max(3000, result.failure["retryAfterMs"].toInt());
                return;
            }
            ++m_batches;
            QSet<QString> queued;
            for (const auto &value : m_player->queue) queued.insert(MusicPlayer::identity(value.toObject()));
            int added = 0;
            const auto items = result.value.toObject()["items"].toArray();
            for (const auto &value : items) {
                const auto track = value.toObject();
                const auto key = MusicPlayer::identity(track);
                if (!song(track) || track["provider"] != m_api.provider || m_seen.contains(key) || queued.contains(key)) continue;
                // The server is batched; never let automatic recommendations grow unbounded.
                if (!m_startPending && upcoming() >= 10) break;
                queued.insert(key); remember(track); m_generated.insert(key); ++added;
                if (m_startPending) startTrack(track);
                else m_player->enqueue(track);
            }
            if (added) m_emptyBatches = 0;
            else if (++m_emptyBatches >= 3) m_error = QStringLiteral("暂时没有新的推荐，稍后点重试");
            continueWaiting();
        }, [self = QPointer(this), generation, request] {
            return self && self->m_active && self->m_generation == generation && self->m_request == request;
        });
}

void RadioController::continueWaiting() {
    if (!m_waiting || m_paused || upcoming() <= 0) return;
    m_waiting = false;
    m_player->playIndex(m_player->index + 1);
}

bool RadioController::advance(int direction, bool ended) {
    if (!m_active) return false;
    if (m_startPending) return true;
    if (ended && m_paused) { m_waiting = true; return true; }
    if (!ended) m_paused = false;
    if (direction < 0) {
        m_waiting = false;
        if (m_player->index > 0) m_player->playIndex(m_player->index - 1);
    } else if (upcoming() > 0) {
        m_waiting = false;
        m_player->playIndex(m_player->index + 1);
    } else {
        m_waiting = true;
        m_player->setPaused(true);
        fetch();
    }
    return true;
}

void RadioController::setPaused(bool paused) {
    m_paused = paused;
    if (m_waiting) { if (!paused) { continueWaiting(); fetch(); } }
    else m_player->setPaused(paused);
}

void RadioController::select(int index, const QString &expectedKey) {
    if (index < 0 || index >= m_player->queue.size()) return;
    const auto track = m_player->queue[index].toObject();
    const auto uiKey = track["provider"].toString() + ":song:" + track["id"].toString();
    if (!expectedKey.isEmpty() && expectedKey != MusicPlayer::identity(track) && expectedKey != uiKey) return;
    m_waiting = m_startPending = m_paused = false;
    m_player->playIndex(index, expectedKey);
}

void RadioController::enqueue(const QJsonObject &track, bool next) {
    if (!song(track)) return;
    const auto key = MusicPlayer::identity(track);
    m_generated.remove(key); remember(track);
    m_player->enqueue(track, next);
    if (!next) {
        // Manual additions play before automatic suggestions, keeping manual order.
        const int last = int(m_player->queue.size()) - 1;
        for (int i = m_player->index + 1; i < last; ++i) {
            if (m_generated.contains(MusicPlayer::identity(m_player->queue[i].toObject()))) {
                m_player->move(last, i, key); break;
            }
        }
    }
    continueWaiting();
}

void RadioController::prune() {
    // Keep twelve past radio entries for Back; never discard manual entries.
    for (int i = m_player->index - 13; i >= 0; --i) {
        const auto key = MusicPlayer::identity(m_player->queue[i].toObject());
        if (m_generated.remove(key)) m_player->remove(i);
    }
}

void RadioController::tick() {
    if (!m_active) return;
    if (credential() != m_credential) { stop(QStringLiteral("电台账号已变更，请重新开启")); return; }
    if (m_busy && m_requestClock.elapsed() > 30000) {
        ++m_request; m_busy = false; m_error = QStringLiteral("推荐请求超时，请检查网络后重试");
        m_nextFetch = m_clock.elapsed() + 3000;
    }
    prune();
    if (!m_player->failed && m_player->state["playing"].toBool() && m_player->state["position"].toDouble() > 5000)
        m_failedTracks = 0;
    const auto failedKey = MusicPlayer::identity(m_player->current);
    if (m_player->failed && !m_paused && m_error.isEmpty() && m_generated.contains(failedKey) && m_failedKey != failedKey) {
        m_failedKey = failedKey;
        if (++m_failedTracks >= 3) m_error = QStringLiteral("连续三首未能播放，请检查账号或网络后重试");
        else advance(1);
    }
    if (!m_paused && (m_startPending || upcoming() <= 2)) fetch();
}

QJsonObject RadioController::snapshot() const {
    const auto phase = !m_active ? "idle" : !m_error.isEmpty() ? "error" : m_paused ? "paused" :
                       m_startPending ? "starting" : m_waiting ? "waiting" : m_busy ? "fetching" : "playing";
    return {{"active", m_active}, {"provider", m_api.provider}, {"busy", m_busy}, {"waiting", m_waiting},
            {"paused", m_paused}, {"phase", phase}, {"error", m_error},
            {"upcoming", m_active ? upcoming() : 0}, {"batches", m_batches},
            {"retryAfterMs", m_error.isEmpty() ? 0 : int(std::max<qint64>(0, m_nextFetch - m_clock.elapsed()))}};
}
