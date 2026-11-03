#include "RadioController.h"
#include <QGuiApplication>
#include <QThread>
#include <QUrl>
#include <iostream>
#include <stdexcept>

static void check(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
static QJsonObject song(const QString &provider, const QString &id) {
    return {{"provider",provider},{"id",id},{"key",provider+":song:"+id},{"kind","song"},{"title",id}};
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    QGuiApplication app(argc,argv);
    try {
        Host host({},true,nullptr,true); host.interval=0;
        MusicApi api(&host); MusicPlayer player(&host,&api);
        RadioController radio(&host,&player);
        player.volume(0);
        player.onEnd=[&] { if (!radio.advance(1,true)) player.next(1,true); };
        const auto wav=QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])).toString();
        int requests=0, serial=0; QString failure;
        bool duplicates=false, failPlayback=false;
        QStringList sources;
        host.fixture=[&](QString route,QJsonObject params) {
            const auto provider=route.split('/').value(2);
            QJsonValue value=QJsonObject{};
            if (route.endsWith("/discover")) {
                ++requests; sources.append(provider);
                if (!failure.isEmpty()) return QJsonObject{{"body",QJsonObject{{"code",503},{"message",failure}}},{"cookies",QJsonArray{}}};
                QJsonArray tracks;
                for(int i=0;i<(provider=="qq"?5:3);++i)
                    tracks.append(song(provider,duplicates?"seed":QString::number(++serial)));
                value=QJsonObject{{"items",tracks},{"more",false}};
            } else if (route.endsWith("/playback")) {
                const auto track=params["args"].toArray()[0].toObject();
                check(track["provider"]==provider,"playback source mismatch");
                if(failPlayback) return QJsonObject{{"body",QJsonObject{{"code",503},{"message","unavailable"}}},{"cookies",QJsonArray{}}};
                value=QJsonObject{{"url",wav},{"type","wav"}};
            }
            return QJsonObject{{"body",QJsonObject{{"code",200},{"value",value}}},{"cookies",QJsonArray{}}};
        };
        QElapsedTimer clock; clock.start();
        auto until=[&](std::function<bool()> predicate,int timeout=7000) {
            const auto deadline=clock.elapsed()+timeout;
            while(clock.elapsed()<deadline) {
                app.processEvents(); player.tick(clock.elapsed()/1000.0,true); radio.tick();
                if(predicate()) return true;
                QThread::msleep(5);
            }
            return false;
        };
        radio.start("qq",song("qq","seed"));
        check(until([&]{return requests==1 && !radio.snapshot()["busy"].toBool() && !player.loading;}),"first batch failed");
        check(player.queue.size()==6 && radio.snapshot()["upcoming"].toInt()==5,"initial QQ queue incorrect");
        host.setCatalogProvider("netease");
        radio.setPaused(true);
        const int pausedRequests=requests;
        check(until([&]{return !player.state["playing"].toBool();}),"pause failed");
        radio.advance(1); radio.advance(1); radio.advance(1);
        check(until([&]{return requests>=2 && !radio.snapshot()["busy"].toBool();}),"low-water prefetch missing");
        check(sources.last()=="qq" && radio.snapshot()["upcoming"].toInt()<=10,"theme changed radio source or buffer unbounded");
        auto manual=song("netease","manual");
        radio.enqueue(manual,false);
        check(player.queue[player.index+1].toObject()["provider"]=="netease","manual insertion priority lost");
        const auto before=player.queue;
        radio.stop(); check(player.queue==before,"stop discarded queue");
        player.stop();
        // Cancellation between request and delivery must leave the queue untouched.
        radio.start("qq"); radio.stop();
        until([&]{return !player.loading;},1000);
        check(player.queue.isEmpty(),"stopped request delivered songs");

        radio.start("netease");
        check(until([&]{return !player.current.isEmpty() && !player.loading;}),"NetEase batch failed");
        check(player.current["provider"]=="netease" && sources.last()=="netease","NetEase dispatch used QQ");
        radio.setPaused(true);
        const auto baseRequests=requests;
        until([&]{return false;},2200);
        check(requests==baseRequests,"paused radio kept fetching");
        radio.stop(); player.stop();

        // End-of-batch waits instead of wrapping to the first old song.
        radio.start("qq",song("qq","seed")); radio.setPaused(true);
        check(until([&]{return !player.loading;}),"seed load failed");
        duplicates=true;
        radio.advance(1);
        check(radio.snapshot()["waiting"].toBool(),"queue tail wrapped");
        check(until([&]{return !radio.snapshot()["error"].toString().isEmpty();},9000),"duplicate loop did not stop");
        const auto duplicateRequests=requests;
        until([&]{return false;},2100);
        check(requests==duplicateRequests && player.current["id"]=="seed","blocked radio retried or replayed seed");
        duplicates=false;
        radio.retry();
        check(until([&]{return player.current["id"]!="seed" && !player.loading;}),"retry did not resume waiting radio");
        radio.stop(); player.stop();

        // User pause during an outstanding request must survive its completion.
        radio.start("netease"); radio.setPaused(true);
        check(until([&]{return !radio.snapshot()["busy"].toBool() && !player.loading;}),"paused start timeout");
        until([&]{return false;},450);
        check(radio.snapshot()["paused"].toBool() && !player.state["playing"].toBool() && !host.mediaState()["requested"].toBool(),"late batch overrode pause");
        radio.select(0,"wrong-key");
        check(radio.snapshot()["paused"].toBool(),"stale list selection changed radio state");
        const auto pausedIndex=player.index;
        radio.advance(1,true);
        check(player.index==pausedIndex && radio.snapshot()["waiting"].toBool(),"late end event overrode pause");
        radio.stop(); player.stop();

        failure="请先登录网易云音乐";
        radio.start("netease");
        check(until([&]{return !radio.snapshot()["error"].toString().isEmpty();}),"auth/network failure missing");
        const auto failedRequests=requests;
        until([&]{return false;},2200);
        check(requests==failedRequests,"error caused request loop");
        failure.clear(); radio.stop(); player.stop();

        // A real credential boundary cancels in-flight recommendation callbacks.
        radio.start("qq"); host.cookies["qqmusic_session"]="fixture-new-account"; radio.tick();
        check(!radio.active(),"account switch did not cancel radio");
        until([&]{return false;},100);
        check(player.queue.isEmpty(),"old account response reached queue");
        host.cookies={};

        failPlayback=true;
        radio.start("netease");
        check(until([&]{return radio.snapshot()["error"].toString().contains(QStringLiteral("连续三首"));}),"unavailable tracks did not stop after three failures");
        const auto lastFailure=player.current["id"].toString();
        const auto stoppedRequests=requests;
        until([&]{return radio.snapshot()["retryAfterMs"].toInt()==0;});
        check(requests==stoppedRequests,"playback failure kept requesting recommendations");
        failPlayback=false; radio.retry();
        check(until([&]{return player.current["id"].toString()!=lastFailure && !player.failed && !player.loading;}),"retry at a failed queue tail did not resume");
        radio.stop(); player.stop();

        radio.start("qq",song("qq","seed"));
        check(until([&]{return !player.loading && !radio.snapshot()["busy"].toBool();}),"final load failed");
        // Natural endings advance and replenish without a GUI or any QML timer.
        check(until([&]{return radio.snapshot()["batches"].toInt()>=2;},13000),"natural playback did not replenish");
        // A manually queued replay is a distinct queue occurrence, not a jump back.
        radio.setPaused(true);
        radio.enqueue(player.current,true);
        const auto repeatIndex=player.index+1;
        radio.advance(1);
        check(player.index==repeatIndex,"manual repeat jumped back to its previous occurrence");
        for(int i=0;i<24;++i) {
            check(until([&]{return radio.snapshot()["upcoming"].toInt()>0;}),"long-run refill stalled");
            radio.advance(1);
        }
        radio.tick();
        check(player.queue.size()<=26,"automatic playback history grew without a bound");
        radio.stop(); player.stop(); host.shutdown();
        std::cout << "PASS: both providers, bounded prefetch, manual priority, pause, theme independence, stale callbacks, no tail wrap, duplicate brake, retry, errors, credential changes, natural refill\n";
    } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
    return 0;
}
