#pragma once
#include "MusicPlayer.h"
#include <QElapsedTimer>
#include <QQueue>

// The service owns the radio. Browsing pages and their lifetime never drive it.
class RadioController : public QObject {
  public:
    RadioController(Host *host, MusicPlayer *player, QObject *parent = nullptr);
    void start(const QString &provider, const QJsonObject &seed = {});
    void stop(const QString &reason = {});
    void retry();
    void tick();
    bool advance(int direction, bool ended = false);
    void setPaused(bool paused);
    void enqueue(const QJsonObject &track, bool next);
    void select(int index, const QString &expectedKey = {});
    bool active() const { return m_active; }
    QJsonObject snapshot() const;

  private:
    Host *m_host;
    MusicPlayer *m_player;
    MusicApi m_api;
    QElapsedTimer m_clock;
    QElapsedTimer m_requestClock;
    QByteArray m_credential;
    QQueue<QString> m_recent;
    QSet<QString> m_seen, m_generated;
    quint64 m_generation = 0, m_request = 0;
    bool m_active = false, m_busy = false, m_waiting = false;
    bool m_startPending = false, m_paused = false;
    int m_emptyBatches = 0, m_failedTracks = 0, m_batches = 0;
    qint64 m_nextFetch = 0;
    QString m_error, m_failedKey;
    QByteArray credential() const;
    int upcoming() const;
    void remember(const QJsonObject &track);
    void fetch();
    void startTrack(const QJsonObject &track);
    void continueWaiting();
    void prune();
};
