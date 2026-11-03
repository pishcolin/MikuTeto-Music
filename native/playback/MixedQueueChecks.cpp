#include "MusicPlayer.h"
#include <QGuiApplication>
#include <QElapsedTimer>
#include <QThread>
#include <QUrl>
#include <iostream>
#include <stdexcept>

static void check(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
static QJsonObject song(QString provider, QString id, bool deferred = false) {
    return {{"provider",provider},{"id",id},{"key",provider+":song:"+id},
            {"kind","song"},{"title",provider+id},{"deferred",deferred}};
}
int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: MikuMixedQueueChecks <one-second-silent.wav>\n";
        return 2;
    }
    QGuiApplication app(argc,argv);
    try {
        Host host({},true,nullptr,true);
        host.interval = 0;
        MusicApi api(&host);
        MusicPlayer player(&host,&api);
        QStringList plays, reads;
        const auto wav=QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])).toString();
        host.fixture=[&](QString route,QJsonObject params) {
            reads.append(route);
            const auto args=params["args"].toArray();
            const auto provider=route.split('/').value(2);
            QJsonValue value=QJsonObject{};
            if (route.endsWith("/songs")) value=QJsonArray{song(provider,args[0].toArray()[0].toString())};
            if (route.endsWith("/playback")) {
                const auto track=args[0].toObject();
                check(track["provider"].toString()==provider,"playback routed to wrong provider");
                plays.append(provider+":"+track["id"].toString());
                value=QJsonObject{{"url",wav},{"type","wav"}};
            }
            return QJsonObject{{"body",QJsonObject{{"code",200},{"value",value}}},{"cookies",QJsonArray{}}};
        };
        QElapsedTimer clock; clock.start();
        auto until=[&](std::function<bool()> predicate,int limit=6000) {
            const auto end=clock.elapsed()+limit;
            while(clock.elapsed()<end) {
                app.processEvents(); player.tick(clock.elapsed()/1000.0,true);
                if(predicate()) return true;
                QThread::msleep(5);
            }
            return false;
        };
        auto qq=song("qq","same"), ne=song("netease","same",true), qq2=song("qq","last");
        QJsonArray queue{qq,ne,qq2,qq};
        player.volume(0);
        player.setMode("off");
        player.play(qq,queue,0,false,QJsonObject{{"position",0},{"requested",false}});
        host.setCatalogProvider("netease");
        check(until([&]{return !player.loading;}),"QQ initial loading timed out");
        check(!player.failed && player.queue.size()==3,"mixed dedup/paused load failed");
        check(api.provider=="qq" && !player.state["playing"].toBool(),"catalog switch changed current playback");
        player.next(1);
        player.setPaused(true);
        check(until([&]{return !player.loading;}),"NetEase deferred loading timed out");
        check(!player.failed && player.current["provider"]=="netease","deferred mixed next failed");
        check(reads.contains("/native/netease/songs"),"deferred lookup used browsing provider");
        check(player.queue[1].toObject()["deferred"].toBool()==false,"deferred queue entry was not hydrated");
        const auto beforeMoves = player.playbackSnapshot();
        const auto requestCount = plays.size();
        player.move(0, 2, qq["key"].toString());
        check(player.index==0 && player.current["provider"]=="netease", "move across current lost current index");
        player.move(0, 1, MusicPlayer::identity(ne));
        check(player.index==1 && player.queue[1].toObject()["provider"]=="netease", "move current lost identity");
        check(plays.size()==requestCount && player.playbackSnapshot()["state"]==beforeMoves["state"],
              "queue move restarted or changed playback");
        const auto movedQueue = player.queue;
        player.move(0, 2, "stale-key"); player.move(-1, 2); player.playIndex(10);
        check(player.queue==movedQueue && plays.size()==requestCount, "invalid/stale queue commands changed playback");
        player.playIndex(1, ne["key"].toString()); player.setPaused(true);
        check(until([&]{return !player.loading;}), "index-only playback timed out");
        check(plays.size()==requestCount+1 && player.current["provider"]=="netease", "UI key rejected by index playback");
        auto saved=player.sessionState(); saved["requested"]=false;
        player.stop(); api.provider="qq";
        player.restoreSessionState(saved);
        check(until([&]{return !player.loading;}),"mixed restore timed out");
        check(!player.failed && player.queue.size()==3 && player.index==1 && api.provider=="netease","mixed restore lost source/index");
        plays.clear(); player.setMode("off"); player.play(qq,queue);
        check(until([&]{return plays.size()>=3;},10000),"natural end did not advance across providers");
        check(plays.mid(0,3)==QStringList{"qq:same","netease:same","qq:last"},"automatic mixed order incorrect");
        player.setPaused(true);
        const auto size=player.queue.size();
        player.accountLoggedOut("qq");
        check(player.failed && player.queue.size()==size,"logout destroyed mixed queue");
        host.shutdown();
        std::cout<<"PASS: mixed identities, source routing, catalog independence, deferred tracks, session restore, automatic QQ -> NetEase -> QQ, logout preserves queue\n";
        return 0;
    } catch(const std::exception &e) {
        std::cerr<<"FAIL: "<<e.what()<<"\n"; return 1;
    }
}
