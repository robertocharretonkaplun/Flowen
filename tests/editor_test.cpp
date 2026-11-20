#include "editor.h"
#include "inlineeditor.h"
#include "svgglyph.h"
#include <QClipboard>
#include <QSettings>
#include <QStandardPaths>
#include <QScopeGuard>
#include <QFile>
#include <QJsonDocument>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTemporaryDir>
#include <QTextCursor>
#include <QTextDocument>
#include <QImage>
#include <cstdio>
#include <QtTest>

using Obj = QJsonObject;
static QQuickItem *visibleItem(QQuickItem *root,const QString &name) {
    if (root->objectName() == name) return root;
    for (auto *child : root->childItems()) {
        if (auto *found = visibleItem(child,name)) return found;
    }
    return nullptr;
}
class EditorTest : public QObject {
    Q_OBJECT
    QTemporaryDir preferences;
private slots:
    void initTestCase() {
        QVERIFY(preferences.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,preferences.path());
        QQuickStyle::setStyle("Basic");
        QLocale::setDefault(QLocale(QLocale::Spanish,QLocale::Mexico));
        InlineEditor::registerType();
        SvgGlyph::registerType();
        // Never read or write the real client configurations while testing.
        for (const auto &dir : {"claude","codex","desktop"}) QVERIFY(QDir(preferences.path()).mkpath(dir));
        qputenv("CLAUDE_CONFIG_DIR",QFile::encodeName(QDir(preferences.path()).filePath("claude")));
        qputenv("FLOWEN_CLAUDE_DESKTOP_CONFIG",QFile::encodeName(QDir(preferences.path()).filePath("desktop/claude_desktop_config.json")));
        if (!qEnvironmentVariableIsSet("FLOWEN_TEST_LIVE_CODEX"))
            qputenv("CODEX_HOME",QFile::encodeName(QDir(preferences.path()).filePath("codex")));
        qputenv("FLOWEN_USAGE_FILE",QFile::encodeName(QDir(preferences.path()).filePath("usage.jsonl")));
    }
    void formattingFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("formato.sqlite3"));
        auto created = store.call("create_page",{{"title","Formato"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Hola mundo bonito"},{"spans",QJsonArray{Obj{{"start",0},{"end",4},{"style",2}}}}},
            Obj{{"type","task"},{"text","Revisar enlaces"}}}}},"manual");
        const QString id = created["id"].toString();
        Editor editor(store);
        // Captures (README) show a sample name, never the Windows account's.
        editor.setAuthor("Ana Ruiz");
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto stored = [&](int index) {
            return QString::fromUtf8(QJsonDocument(store.page(id)["blocks"].toArray()[index].toObject()["spans"].toArray()).toJson(QJsonDocument::Compact));
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(250);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto *bubble = window->findChild<QQuickItem *>("selectionBubble");
        QVERIFY(bubble);
        QCOMPARE(js("blockRepeater.itemAt(0).formatter.spans()").toString(),QString(R"([{"end":4,"start":0,"style":2}])"));
        QVERIFY(!bubble->property("shown").toBool());

        // Dragging a selection keeps the menu hidden until the mouse is released.
        auto *field = qvariant_cast<QQuickItem *>(js("blockRepeater.itemAt(0).editor"));
        QVERIFY(field);
        auto at = [&](int position) {
            QRectF r;
            QMetaObject::invokeMethod(field,"positionToRectangle",Q_RETURN_ARG(QRectF,r),Q_ARG(int,position));
            return field->mapToScene(QPointF(r.x()+1,r.y()+r.height()/2)).toPoint();
        };
        QTest::mousePress(window,Qt::LeftButton,Qt::NoModifier,at(11));
        QTest::mouseMove(window,at(14));
        QTest::mouseMove(window,at(17));
        QTest::qWait(250);
        QVERIFY(!bubble->property("shown").toBool());
        QTest::mouseRelease(window,Qt::LeftButton,Qt::NoModifier,at(17));
        QTRY_VERIFY(bubble->property("shown").toBool());
        QCOMPARE(field->property("selectedText").toString(),QString("bonito"));

        js("blockRepeater.itemAt(0).editor.select(5,10)");
        QTRY_VERIFY(bubble->property("shown").toBool());
        QCOMPARE(bubble->property("kind").toString(),QString("paragraph"));
        QTest::keyClick(window,Qt::Key_B,Qt::ControlModifier);
        QTRY_COMPARE(bubble->property("styles").toInt(),1);

        // Clicking a format button keeps the focus and the selection in the text.
        auto *italic = window->findChild<QQuickItem *>("formatItalic");
        QVERIFY(italic);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,italic->mapToScene(QPointF(italic->width()/2,italic->height()/2)).toPoint());
        QTRY_COMPARE(bubble->property("styles").toInt(),3);
        QVERIFY(field->hasActiveFocus());
        QCOMPARE(field->property("selectedText").toString(),QString("mundo"));

        // Ctrl+K with a selection opens the link field instead of the page search.
        QTest::keyClick(window,Qt::Key_K,Qt::ControlModifier);
        QTRY_COMPARE(bubble->property("mode").toString(),QString("link"));
        QVERIFY(!js("search.activeFocus").toBool());
        type("no es un enlace");
        QTest::keyClick(window,Qt::Key_Return);
        QVERIFY(!bubble->property("linkError").toString().isEmpty());
        js("bubble.openLink()");
        type("ejemplo.com/guia");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(bubble->property("mode").toString(),QString("menu"));
        QCOMPARE(js("blockRepeater.itemAt(0).formatter.activeLink").toString(),QString("https://ejemplo.com/guia"));
        QVERIFY(field->hasActiveFocus());
        capture("formato");
        // "Color" opens the palette for the text and its background; the choice stays on the selection.
        auto *colorRow = visibleItem(window->contentItem(),"bubbleColor");
        QVERIFY(colorRow);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,colorRow->mapToScene(colorRow->boundingRect().center()).toPoint());
        QTRY_VERIFY(js("bubble.menuOpen").toBool());
        QQuickItem *red = nullptr;
        QTRY_VERIFY((red = visibleItem(window->contentItem(),"textTone-red")) != nullptr);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,red->mapToScene(red->boundingRect().center()).toPoint());
        QTRY_COMPARE(js("blockRepeater.itemAt(0).formatter.activeColor").toString(),QString("red"));
        QVERIFY(field->hasActiveFocus());
        capture("color");
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY2(!js("bubble.menuOpen").toBool(),qPrintable(js("'shown ' + bubble.shown + ' palette ' + bubble.paletteOpen + ' focus ' + (activeFocusItem ? activeFocusItem.objectName + '/' + activeFocusItem : 'none')").toString()));
        js("blockRepeater.itemAt(0).formatter.setColor('')");

        // "Comentar" opens a card beside the text, as in Google Docs.
        js("bubble.openComment()");
        auto *draft = window->findChild<QQuickItem *>("commentDraft");
        QVERIFY(draft);
        QTRY_VERIFY(draft->isVisible());
        QTRY_VERIFY(!bubble->property("shown").toBool());
        type("Confirmar la fuente en https://ejemplo.com");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_VERIFY(!draft->isVisible());
        QCOMPARE(js("blockRepeater.itemAt(0).formatter.activeComment").toString(),QString("Confirmar la fuente en https://ejemplo.com"));
        const QString thread = js("blockRepeater.itemAt(0).formatter.activeThread").toString();
        QVERIFY(!thread.isEmpty());
        QCOMPARE(js("activeComment").toString(),thread);
        QTRY_COMPARE(js("pageComments.length").toInt(),1);
        capture("comentario");

        // Reply from the card's field.
        auto *answer = visibleItem(window->contentItem(),"commentReply");
        QVERIFY(answer && answer->isVisible());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,answer->mapToScene(QPointF(answer->width()/2,answer->height()/2)).toPoint());
        QTRY_VERIFY(answer->hasActiveFocus());
        type("Revisado");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(js("pageComments[0].replies.length").toInt(),1);
        capture("comentario-respuesta");

        js("bubble.kindChosen('heading')");
        QCOMPARE(js("blocks.get(0).kind").toString(),QString("heading"));

        QVERIFY(js("flush()").toBool());
        auto spans = QJsonDocument::fromJson(stored(0).toUtf8()).array();
        QCOMPARE(spans.size(),2);
        QCOMPARE(spans[0].toObject(),(Obj{{"start",0},{"end",4},{"style",2}}));
        auto commented = spans[1].toObject();
        QCOMPARE(commented["comment"].toString(),QString("Confirmar la fuente en https://ejemplo.com"));
        QCOMPARE(commented["link"].toString(),QString("https://ejemplo.com/guia"));
        QCOMPARE(commented["style"].toInt(),3);
        auto meta = commented["thread"].toObject();
        QCOMPARE(meta["id"].toString(),thread);
        QCOMPARE(meta["author"].toString(),editor.author());
        QVERIFY(!meta["at"].toString().isEmpty());
        QCOMPARE(meta["resolved"].toBool(),false);
        QCOMPARE(meta["replies"].toArray().first().toObject()["text"].toString(),QString("Revisado"));
        QCOMPARE(store.page(id)["blocks"].toArray()[0].toObject()["type"].toString(),QString("heading"));

        // Resolving hides the card; Ctrl+Z in the text brings it back. Reloading keeps the thread.
        auto *resolve = visibleItem(window->contentItem(),"commentResolve");
        QVERIFY(resolve && resolve->isVisible());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,resolve->mapToScene(QPointF(resolve->width()/2,resolve->height()/2)).toPoint());
        QTRY_VERIFY(js("pageComments[0].resolved").toBool());
        QTRY_COMPARE(js("rail.shown.length").toInt(),0);
        js("blockRepeater.itemAt(0).focusEditor()");
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QTRY_VERIFY(!js("pageComments[0].resolved").toBool());
        QVERIFY(js("flush()").toBool());
        js("showPage(currentId)");
        QCOMPARE(js("blockRepeater.itemAt(0).formatter.spans()").toString(),stored(0));
        QCOMPARE(js("blockRepeater.itemAt(0).editor.text").toString(),QString("Hola mundo bonito"));

        // Typing over the selection hides the menu and keeps the plain text in sync.
        js("blockRepeater.itemAt(1).focusEditor(); blockRepeater.itemAt(1).editor.select(8,15)");
        QTRY_VERIFY(bubble->property("shown").toBool());
        QCOMPARE(bubble->property("kind").toString(),QString("task"));
        type("notas");
        QTRY_VERIFY(!bubble->property("shown").toBool());
        QCOMPARE(js("blocks.get(1).body").toString(),QString("Revisar notas"));
        QVERIFY(window->close());
    }
    void editorFlow() {
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        const auto path = temporary.filePath("original.sqlite3");
        notes::Store gui(path);
        Editor editor(gui);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(win);
        win->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(win));
        auto eval = [&](const QString &expression) {
            QQmlExpression js(qmlContext(win),win,expression);
            auto value = js.evaluate();
            if (js.hasError()) QTest::qFail(qPrintable(js.error().toString()),__FILE__,__LINE__);
            return value;
        };
        eval("newPage(null)");
        QString id = win->property("currentId").toString();
        QVERIFY2(!id.isEmpty(),qPrintable(win->property("notice").toString()));
        QTest::keyClick(win,Qt::Key_A,Qt::ControlModifier);
        for (auto k : {Qt::Key_N,Qt::Key_O,Qt::Key_T,Qt::Key_A}) QTest::keyClick(win,k);
        auto *title = win->findChild<QQuickItem *>("titleInput");
        QVERIFY(title);
        QCOMPARE(title->property("text").toString(),QString("nota"));
        eval("blockRepeater.itemAt(0).focusEditor()");
        QTest::keyClick(win,Qt::Key_X);
        QTRY_COMPARE_WITH_TIMEOUT(gui.page(id)["revision"].toInt(),2,3000);
        auto first = gui.page(id);
        QCOMPARE(first["blocks"].toArray().first().toObject()["text"].toString(),QString("x"));
        QVERIFY(!win->property("dirty").toBool());
        QProcess external;
        external.start(QCoreApplication::applicationDirPath()+"/notas-mcp",{"--db",path});
        QVERIFY(external.waitForStarted());
        auto send = [&](const Obj &packet) {
            external.write(QJsonDocument(packet).toJson(QJsonDocument::Compact)+"\n");
        };
        auto rpc = [&](int request, const QString &method, const Obj &params) {
            send({{"jsonrpc","2.0"},{"id",request},{"method",method},{"params",params}});
            while (!external.canReadLine() && external.waitForReadyRead(3000)) {}
            return QJsonDocument::fromJson(external.readLine()).object()["result"].toObject();
        };
        QVERIFY(rpc(1,"initialize",{{"protocolVersion","2025-11-25"},{"capabilities",Obj{}},
                    {"clientInfo",Obj{{"name","editor_test"},{"version","1"}}}}).contains("serverInfo"));
        send({{"jsonrpc","2.0"},{"method","notifications/initialized"}});
        auto tool = [&](int request, const QString &name, const Obj &args) {
            auto result = rpc(request,"tools/call",{{"name",name},{"arguments",args}});
            return result.contains("content") && !result["isError"].toBool();
        };
        QVERIFY(tool(2,"apply_block_changes",{{"id",id},{"expected_revision",2},{"changes",QJsonArray{
            Obj{{"op","insert"},{"block",Obj{{"type","task"},{"text","Revisar la edición"}}}}}}}));
        QTRY_COMPARE_WITH_TIMEOUT(win->property("revision").toInt(),3,3000);
        QCOMPARE(eval("draft().length").toInt(),2);
        eval("titleInput.forceActiveFocus(); titleInput.selectAll()");
        QTest::keyClick(win,Qt::Key_Z);
        QVERIFY(tool(3,"update_page",{{"id",id},{"expected_revision",3},{"title","Externa"}}));
        QTRY_VERIFY_WITH_TIMEOUT(win->property("conflict").toBool(),3000);
        QCOMPARE(title->property("text").toString(),QString("z"));
        QVERIFY(!win->close());
        QVERIFY(win->property("dirty").toBool());
        QCOMPARE(gui.page(id)["title"].toString(),QString("Externa"));
        eval("showPage(currentId)");
        QVERIFY(eval("action('restore_revision',{target:2})").toBool());
        auto restored = gui.page(id);
        QCOMPARE(restored["title"],first["title"]);
        QCOMPARE(restored["blocks"],first["blocks"]);
        QCOMPARE(restored["revision"].toInt(),5);
        auto revisions = gui.history(id);
        QCOMPARE(revisions.size(),5);
        QCOMPARE(revisions.at(1).toObject()["actor"].toString(),QString("mcp"));
        auto md = temporary.filePath("nota.md");
        auto result = editor.run("export",{{"id",id},{"url",QUrl::fromLocalFile(md).toString()}});
        QVERIFY(result["ok"].toBool());
        QFile file(md);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(),QByteArray("# nota\n\nx\n\n"));
        auto copy = temporary.filePath("copia.sqlite3");
        gui.backup(copy);
        notes::Store recovered(copy,true);
        QCOMPARE(recovered.page(id),restored);
        QCOMPARE(recovered.history(id),revisions);
        QVERIFY_THROWS_EXCEPTION(notes::Error,gui.backup(copy));
        QVERIFY(win->close());
        external.closeWriteChannel();
        QVERIFY(external.waitForFinished(3000));
        QCOMPARE(external.exitCode(),0);
    }
    void photosAndSaveAs() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        const QString db = temp.filePath("notas.sqlite3");
        notes::Store store(db);
        const QString title = "Ensayo <luz> & color";
        auto page = store.call("create_page",{{"title",title},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Prueba de fotografía."}}}}},"manual");
        const auto id = page["id"].toString();
        Editor editor(store);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(win);
        win->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(win));
        auto eval = [&](const QString &code) {
            QQmlExpression expr(qmlContext(win),win,code);
            auto value = expr.evaluate();
            if (expr.hasError()) QTest::qFail(qPrintable(expr.error().toString()),__FILE__,__LINE__);
            return value;
        };
        QImage sample(160,80,QImage::Format_RGB32);
        sample.fill(QColor("#357f94"));
        const auto source = temp.filePath("Estudio de color.png");
        QVERIFY(sample.save(source));
        engine.rootContext()->setContextProperty("testImageUrl",QUrl::fromLocalFile(source));
        QVERIFY(eval("insertPhoto(testImageUrl)").toBool());
        auto p = store.page(id);
        // The photo goes under the page's text, with an empty paragraph after it to keep writing.
        QCOMPARE(p["blocks"].toArray().size(),3);
        auto photo = p["blocks"].toArray()[1].toObject();
        const auto asset = photo["asset"].toString();
        QCOMPARE(photo["type"].toString(),QString("image"));
        QVERIFY(QFile::remove(source));
        QVERIFY(!editor.photoUrl(asset).isEmpty());
        QQuickItem *item = nullptr;
        QTRY_VERIFY((item = visibleItem(win->contentItem(),"pagePhoto")) != nullptr);
        QTRY_VERIFY(item->property("status").toInt() == 1);
        auto *grip = visibleItem(win->contentItem(),"photoResizeGrip");
        QVERIFY(grip);
        QTRY_VERIFY(item->width() > 150 && item->height() > 50 && grip->width() > 10);
        // The page scrolls the new photo into view first.
        QTRY_VERIFY(!eval("revealTimer.running").toBool());
        QTest::qWait(100);
        const QPoint start = grip->mapToScene(QPointF(grip->width()/2,grip->height()/2)).toPoint();
        const QPoint end = start-QPoint(qRound(item->width()*0.45),0);
        QTest::mousePress(win,Qt::LeftButton,Qt::NoModifier,start);
        std::function<QString(QQuickItem *)> under = [&](QQuickItem *at) -> QString {
            QString found;
            for (auto *child : at->childItems()) {
                if (!child->isVisible()) continue;
                const QPointF local = child->mapFromScene(start);
                if (child->contains(local)) found = QString("%1(%2) > %3").arg(child->metaObject()->className(),child->objectName(),under(child));
            }
            return found;
        };
        QVERIFY2(grip->property("pressed").toBool(),qPrintable(QString("Tirador en %1,%2; imagen %3×%4; %5").arg(start.x()).arg(start.y()).arg(item->width()).arg(item->height()).arg(under(win->contentItem()))));
        QTest::mouseMove(win,end,40);
        QTRY_COMPARE(eval("draft()[1].width_percent").toInt(),55);
        QTest::mouseRelease(win,Qt::LeftButton,Qt::NoModifier,end);
        QCOMPARE(eval("draft()[1].width_percent").toInt(),55);
        auto *spin = visibleItem(win->contentItem(),"photoWidth");
        QVERIFY(spin);
        spin->forceActiveFocus();
        QTest::keyClick(win,Qt::Key_Up);
        QCOMPARE(eval("draft()[1].width_percent").toInt(),60);
        QTest::keyClick(win,Qt::Key_Down);
        QVERIFY(eval("flush()").toBool());
        QCOMPARE(store.page(id)["blocks"].toArray()[1].toObject()["width_percent"].toInt(),55);
        QTRY_VERIFY(std::abs(item->width()/item->height()-2.0) < 0.04);
        eval("showPage(currentId)");
        QCOMPARE(eval("draft()[1].width_percent").toInt(),55);
        const QString preview = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
        if (!preview.isEmpty()) {
            QTest::qWait(150);
            QVERIFY(win->grabWindow().save(QDir(preview).filePath("foto-editor.png")));
        }
        QString mime;
        auto bytes = store.photo(asset,mime);
        const auto copy = temp.filePath("backup.sqlite3");
        store.backup(copy);
        notes::Store recovered(copy,true);
        QCOMPARE(recovered.photo(asset,mime),bytes);
        QCOMPARE(recovered.page(id),store.page(id));
        eval("fileAction='export'; fileDialog.selectedNameFilter.index=1");
        QCOMPARE(eval("fileDialog.defaultSuffix").toString(),QString("pdf"));
        QCOMPARE(QFileInfo(editor.suggestedFile(QUrl::fromLocalFile(temp.path()),"Ensayo: luz").toLocalFile()).fileName(),QString("Ensayo luz"));
        for (const auto ext : {"md","pdf","html","txt"}) {
            const auto path = temp.filePath("Página #1."+QString(ext));
            auto result = editor.run("export",{{"id",id},{"url",QUrl::fromLocalFile(path).toString()}});
            QVERIFY2(result["ok"].toBool(),qPrintable(result["message"].toString()));
            QFile file(path);
            QVERIFY(file.open(QIODevice::ReadOnly));
            const auto data = file.readAll();
            if (QString(ext) == "md") {
                QVERIFY(data.contains("width=\"55%\""));
                QVERIFY(data.contains("P%C3%A1gina%20%231.media/"));
                QFile media(temp.filePath("Página #1.media/"+asset+".png"));
                QVERIFY(media.open(QIODevice::ReadOnly));
                QCOMPARE(media.readAll(),bytes);
            } else if (QString(ext) == "html") {
                QVERIFY(data.contains("&lt;luz&gt; &amp; color"));
                QVERIFY(data.contains("data:image/png;base64,"+bytes.toBase64()));
                QVERIFY(data.contains("width=\"55%\""));
            } else if (QString(ext) == "pdf") {
                QVERIFY(data.startsWith("%PDF-"));
                QVERIFY(data.contains("/Subtype /Image"));
                QVERIFY(data.trimmed().endsWith("%%EOF"));
                if (!preview.isEmpty()) {
                    QFile proof(QDir(preview).filePath("foto-exportada.pdf"));
                    QVERIFY(proof.open(QIODevice::WriteOnly));
                    QCOMPARE(proof.write(data),data.size());
                }
            } else {
                QVERIFY(data.contains(title.toUtf8()));
                QVERIFY(data.contains("[Foto] Estudio de color"));
            }
        }
        auto r = store.restoreRevision(id,3,2);
        QCOMPARE(r["revision"].toInt(),4);
        QCOMPARE(store.page(id)["blocks"].toArray()[1].toObject()["width_percent"].toInt(),100);
        const auto jpg = temp.filePath("foto.jpg");
        QVERIFY(sample.save(jpg));
        auto added = editor.run("insert_photo",{{"url",QUrl::fromLocalFile(jpg)},{"expected_revision",4},{"id",id}});
        QVERIFY2(added["ok"].toBool(),qPrintable(added["message"].toString()));
        const auto last = store.page(id)["blocks"].toArray().last().toObject();
        QVERIFY(!store.photo(last["asset"].toString(),mime).isEmpty());
        QCOMPARE(mime,QString("image/jpeg"));
        QVERIFY(win->close());
    }
    void settingsTab() {
        QTemporaryDir temp;
        notes::Store store(temp.filePath("Página abierta.sqlite3"));
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        win->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(win));
        auto *link = editor.assistant()->link();
        QTRY_COMPARE(link->tools().size(),8);
        auto js = [&](const QString &code) {
            QQmlExpression expr(qmlContext(win),win,code);
            auto result = expr.evaluate();
            if (expr.hasError()) QTest::qFail(qPrintable(expr.error().toString()),__FILE__,__LINE__);
            return result;
        };
        auto click = [&](const QString &name) {
            QTest::qWait(100);
            auto *item = visibleItem(win->contentItem(),name);
            QVERIFY(item && item->isVisible() && item->width() > 0 && item->height() > 0);
            const auto pos = item->mapToScene(item->boundingRect().center()).toPoint();
            QTest::mousePress(win,Qt::LeftButton,Qt::NoModifier,pos);
            QVERIFY2(item->property("pressed").toBool(),qPrintable(QString("%1 en %2, %3").arg(name).arg(pos.x()).arg(pos.y())));
            QTest::mouseRelease(win,Qt::LeftButton,Qt::NoModifier,pos);
        };
        js("newPage(null); titleInput.text='Mi borrador'");
        const auto id = win->property("currentId").toString();
        click("connectorsTab");
        QTRY_VERIFY(win->property("settingsShown").toBool());
        click("toggleLocalMcp");
        QTRY_COMPARE(link->state(),QString("offline"));
        QVERIFY(link->tools().isEmpty());
        click("toggleLocalMcp");
        QTRY_COMPARE(link->tools().size(),8);
        link->setAutoConnect(false);
        {
            WritingAssistant next(store.path(),QCoreApplication::applicationFilePath());
            QTest::qWait(60);
            QCOMPARE(next.link()->state(),QString("offline"));
        }
        link->setAutoConnect(true);
        click("editorTab");
        QTRY_VERIFY(!win->property("settingsShown").toBool());
        QVERIFY(js("flush()").toBool());
        QCOMPARE(store.page(id)["title"].toString(),QString("Mi borrador"));
        QVERIFY(win->close());
    }
    void connectorsFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("notas del día.sqlite3"));
        const QString codex = CodexConnector::findProgram();
        Editor editor(store,codex.isEmpty() ? QCoreApplication::applicationFilePath() : codex);
        auto *hub = editor.assistant()->connectors();
        const QString server = QDir::toNativeSeparators(McpLink::serverPath());
        const QString db = QDir::toNativeSeparators(QFileInfo(store.path()).absoluteFilePath());
        auto readJson = [](const QString &path) {
            QFile file(path);
            return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : Obj();
        };
        auto writeText = [](const QString &path, const QByteArray &text) {
            QFile file(path);
            QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
            file.write(text);
        };

        // Claude Desktop keeps the other servers and settings in its file.
        auto *desktop = hub->claudeDesktop();
        const QString desktopFile = ClaudeDesktopConnector::findConfig();
        QVERIFY(desktopFile.startsWith(QDir(preferences.path()).absolutePath()));
        writeText(desktopFile,R"({"mcpServers":{"otro":{"command":"node","args":["servidor.js"]}},"preferences":{"tema":"oscuro"}})");
        desktop->inspect();
        QTRY_COMPARE(desktop->state(),QString("off"));
        desktop->setEnabled(true);
        QTRY_COMPARE(desktop->state(),QString("on"));
        QCOMPARE(desktop->serverName(),QString("flowen"));
        auto config = readJson(desktopFile);
        QCOMPARE(config["preferences"].toObject()["tema"].toString(),QString("oscuro"));
        QCOMPARE(config["mcpServers"].toObject()["otro"].toObject()["command"].toString(),QString("node"));
        auto entry = config["mcpServers"].toObject()["flowen"].toObject();
        QCOMPARE(entry["command"].toString(),server);
        QCOMPARE(entry["args"].toArray(),QJsonArray({"--db",db}));
        QVERIFY(QFile::exists(desktopFile+".flowen-backup"));
        desktop->setEnabled(false);
        QTRY_COMPARE(desktop->state(),QString("off"));
        config = readJson(desktopFile);
        QVERIFY(!config["mcpServers"].toObject().contains("flowen"));
        QVERIFY(config["mcpServers"].toObject().contains("otro"));
        // A broken file is reported and left untouched.
        writeText(desktopFile,"{ roto");
        desktop->setEnabled(true);
        QTRY_COMPARE(desktop->state(),QString("error"));
        QFile broken(desktopFile);
        QVERIFY(broken.open(QIODevice::ReadOnly));
        QCOMPARE(broken.readAll(),QByteArray("{ roto"));
        broken.close();
        // An entry left by a moved package is repaired under the same name.
        writeText(desktopFile,QJsonDocument(Obj{{"mcpServers",Obj{{"flowen",Obj{{"command","C:/ya/no/existe/notas-mcp.exe"},
            {"args",QJsonArray{"--db",db}}}}}}}).toJson());
        desktop->inspect();
        QTRY_COMPARE(desktop->state(),QString("outdated"));
        desktop->setEnabled(true);
        QTRY_COMPARE(desktop->state(),QString("on"));
        QCOMPARE(readJson(desktopFile)["mcpServers"].toObject()["flowen"].toObject()["command"].toString(),server);

        // Codex: enable, pause with its own `enabled` flag, resume and unregister.
        if (!codex.isEmpty()) {
            auto *client = hub->codex();
            client->inspect();
            QTRY_COMPARE_WITH_TIMEOUT(client->state(),QString("off"),20000);
            client->setEnabled(true);
            QTRY_COMPARE_WITH_TIMEOUT(client->state(),QString("on"),40000);
            QCOMPARE(client->serverName(),QString("flowen"));
            client->setEnabled(false);
            QTRY_COMPARE_WITH_TIMEOUT(client->state(),QString("paused"),20000);
            QFile toml(CodexConnector::configFile());
            QVERIFY(toml.open(QIODevice::ReadOnly));
            QVERIFY(toml.readAll().contains("enabled = false"));
            toml.close();
            client->setEnabled(true);
            QTRY_COMPARE_WITH_TIMEOUT(client->state(),QString("on"),20000);
            notes::Store otherStore(temp.filePath("otro proyecto.sqlite3"));
            CodexConnector other(otherStore.path());
            other.setProgram(codex);
            other.setEnabled(true);
            QTRY_COMPARE_WITH_TIMEOUT(other.state(),QString("on"),40000);
            QVERIFY(other.serverName().startsWith("flowen-"));
            client->remove();
            QTRY_COMPARE_WITH_TIMEOUT(client->state(),QString("off"),40000);
        }

        // Claude Code: user scope through its own CLI.
        auto *code = hub->claudeCode();
        if (!code->program().isEmpty()) {
            code->inspect();
            QTRY_COMPARE_WITH_TIMEOUT(code->state(),QString("off"),20000);
            code->setEnabled(true);
            QTRY_COMPARE_WITH_TIMEOUT(code->state(),QString("on"),40000);
            entry = readJson(ClaudeCodeConnector::configFile())["mcpServers"].toObject()["flowen"].toObject();
            QCOMPARE(entry["command"].toString(),server);
            QCOMPARE(entry["args"].toArray(),QJsonArray({"--db",db}));
            code->setEnabled(false);
            QTRY_COMPARE_WITH_TIMEOUT(code->state(),QString("off"),40000);
        }

        hub->copyConfiguration();
        auto copied = QJsonDocument::fromJson(QGuiApplication::clipboard()->text().toUtf8()).object()["mcpServers"].toObject()["flowen"].toObject();
        QCOMPARE(QFileInfo(copied["args"].toArray().at(1).toString()),QFileInfo(store.path()));
        QCOMPARE(QFileInfo(copied["command"].toString()),QFileInfo(McpLink::serverPath()));

        // The tab: Ctrl+, opens it and each switch drives its client.
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        win->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(win));
        QTest::keyClick(win,Qt::Key_Comma,Qt::ControlModifier);
        QTRY_VERIFY(win->property("settingsShown").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(!desktop->busy() && !hub->codex()->busy() && !code->busy(),20000);
        desktop->setEnabled(false);
        QTRY_COMPARE(desktop->state(),QString("off"));
        auto *toggle = visibleItem(win->contentItem(),"toggle-claude-desktop");
        QVERIFY(toggle && toggle->isVisible() && toggle->isEnabled());
        QTest::qWait(120);
        const auto point = toggle->mapToScene(toggle->boundingRect().center()).toPoint();
        QTest::mouseClick(win,Qt::LeftButton,Qt::NoModifier,point);
        QTRY_COMPARE(desktop->state(),QString("on"));
        QVERIFY(toggle->property("checked").toBool());
        const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
        if (!dir.isEmpty()) {
            QTest::qWait(250);
            QVERIFY(win->grabWindow().save(QDir(dir).filePath("conectores.png")));
        }
        QVERIFY(win->close());
    }
    void writingFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("editor.sqlite3"));
        QString original = "Para la próxima revisión, revisar  el  resumen. Después, revisar  el  resumen.";
        QString selected = "revisar  el  resumen";
        auto created = store.call("create_page",{{"title","Notas de la reunión"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text",original}},Obj{{"type","task"},{"text","Compartir el resumen con el equipo."}}}}},"manual");
        QString id = created["id"].toString();
        const bool live = qEnvironmentVariableIsSet("FLOWEN_TEST_LIVE_CODEX");
        Editor editor(store,live ? QString() : QCoreApplication::applicationFilePath());
        auto *assistant = editor.assistant();
        assistant->setEngine("codex");
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTRY_COMPARE_WITH_TIMEOUT(assistant->link()->state(),QString("connected"),10000);
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto choose = [&] {
            js(QString("blockRepeater.itemAt(0).focusEditor(); blockRepeater.itemAt(0).editor.select(%1,%2)")
                .arg(original.lastIndexOf(selected)).arg(original.lastIndexOf(selected)+selected.size()));
            QVERIFY(js("canEditSelection").toBool());
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(250);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        choose();
        capture("seleccion");
        QTest::keyClick(window,Qt::Key_I,Qt::ControlModifier|Qt::ShiftModifier);
        QTRY_VERIFY(js("writing.visible").toBool());
        QCOMPARE(js("writing.selection.original").toString(),selected);
        js("writing.settingsRequested()");
        QTRY_VERIFY(!js("writing.visible").toBool() && js("settingsShown").toBool());
        js("workspaceTabs.currentIndex = 0");
        QTRY_VERIFY(js("writing.visible").toBool());
        QCOMPARE(js("writing.selection.original").toString(),selected);
        auto generate = [&] {
            js("assistant.generate(writing.selection,'Elimina los espacios duplicados y conserva exactamente las palabras y las minúsculas.')");
            QTRY_VERIFY_WITH_TIMEOUT(assistant->phase() != "generating",live ? 190000 : 8000);
            QVERIFY2(assistant->phase() == "preview",qPrintable(assistant->error()));
        };
        generate();
        QCOMPARE(assistant->proposal(),QString("revisar el resumen"));
        // Codex reports usage in its JSONL events; cached input is counted apart.
        const auto spent = assistant->usage()->last();
        QCOMPARE(spent["engine"].toString(),QString("codex"));
        QCOMPARE(spent["input"].toLongLong(),800);
        QCOMPARE(spent["cacheRead"].toLongLong(),100);
        QCOMPARE(spent["output"].toLongLong(),50);
        QCOMPARE(spent["total"].toLongLong(),950);
        QCOMPARE(store.page(id)["revision"].toInt(),1);
        capture("propuesta");
        if (!live) {
            js("writing.close()");
            QTRY_COMPARE(assistant->phase(),QString("idle"));
            QCOMPARE(store.page(id)["revision"].toInt(),1);
            choose(); js("openWriting()"); generate();
            store.call("update_page",{{"id",id},{"expected_revision",1},{"title","Notas de la reunión actualizadas"}},"mcp");
            assistant->apply();
            QTRY_COMPARE(assistant->phase(),QString("error"));
            QCOMPARE(store.page(id)["blocks"].toArray().first().toObject()["text"],original);
            js("writing.close(); showPage(currentId)");
            choose(); js("openWriting()"); generate();
        }
        assistant->apply();
        QTRY_COMPARE(assistant->phase(),QString("idle"));
        QTRY_VERIFY(!js("writing.visible").toBool());
        QString expected = original;
        expected.replace(expected.lastIndexOf(selected),selected.size(),"revisar el resumen");
        auto after = store.page(id);
        QCOMPARE(after["blocks"].toArray()[0].toObject()["text"],expected);
        QCOMPARE(after["blocks"].toArray()[1].toObject()["text"],QString("Compartir el resumen con el equipo."));
        QCOMPARE(store.history(id).first().toObject()["actor"],QString("mcp"));
        assistant->link()->close();
        QCOMPARE(assistant->link()->state(),QString("offline"));
        assistant->link()->open();
        QTRY_COMPARE(assistant->link()->state(),QString("connected"));
        QVERIFY(window->close());
    }
    void composeFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("crear.sqlite3"));
        const QString id = store.call("create_page",{{"title","Prototipos"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Notas de la clase."}},Obj{{"type","paragraph"},{"text",""}}}}},"manual")["id"].toString();
        const QString fake = QCoreApplication::applicationFilePath();
        Editor editor(store,fake,fake);
        auto *assistant = editor.assistant();
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTRY_COMPARE_WITH_TIMEOUT(assistant->link()->state(),QString("connected"),10000);
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(250);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        assistant->setEngine("claude");
        QTRY_COMPARE(assistant->claudeAccount(),QString("in"));
        auto *composer = window->findChild<QQuickItem *>("aiComposer");
        QVERIFY(composer);

        // Space on an empty line opens the prompt with suggestions, as in Notion.
        js("blockRepeater.itemAt(1).focusEditor()");
        QTest::keyClick(window,Qt::Key_Space);
        QTRY_VERIFY(composer->property("active").toBool());
        QVERIFY(composer->property("showSuggestions").toBool());
        QCOMPARE(js("blocks.get(1).body").toString(),QString());
        capture("crear-con-ia");
        type("Crea una serie de puntos sobre prototipado");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE_WITH_TIMEOUT(assistant->phase(),QString("preview"),15000);
        const auto blocks = assistant->blocks();
        QCOMPARE(blocks.size(),4);
        QCOMPARE(blocks[0].toMap()["text"].toString(),QString("Prototipado en videojuegos"));
        QCOMPARE(blocks[1].toMap()["text"].toString(),QString("Probar ideas rápido"));
        QCOMPARE(blocks[3].toMap()["text"].toString(),QString("Hacer un prototipo en papel"));
        capture("crear-con-ia-propuesta");
        const auto spent = assistant->usage()->last();
        QCOMPARE(spent["engine"].toString(),QString("claude"));
        QCOMPARE(spent["kind"].toString(),QString("create"));
        QCOMPARE(spent["total"].toLongLong(),6920);
        QCOMPARE(spent["window"].toLongLong(),200000);
        QCOMPARE(spent["model"].toString(),QString("claude-sonnet-prueba"));
        QCOMPARE(spent["cost"].toDouble(),0.0123);

        // Enter on the empty prompt inserts; the empty line is replaced by the new blocks.
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(store.page(id)["revision"].toInt(),2);
        const auto saved = store.page(id)["blocks"].toArray();
        QCOMPARE(saved.size(),5);
        QCOMPARE(saved[0].toObject()["text"].toString(),QString("Notas de la clase."));
        QCOMPARE(saved[1].toObject()["type"].toString(),QString("heading"));
        QCOMPARE(saved[2].toObject()["type"].toString(),QString("list"));
        QCOMPARE(saved[4].toObject()["type"].toString(),QString("task"));
        QCOMPARE(saved[4].toObject()["checked"].toBool(),false);
        QCOMPARE(store.history(id).first().toObject()["actor"].toString(),QString("mcp"));
        QTRY_VERIFY(!composer->property("active").toBool());
        QTRY_COMPARE(js("blocks.count").toInt(),5);

        // Ctrl+J at the end of the page; a usage limit offers the other assistant.
        js("blockRepeater.itemAt(4).focusEditor()");
        QTest::keyClick(window,Qt::Key_J,Qt::ControlModifier);
        QTRY_VERIFY(composer->property("active").toBool());
        type("FALLA_LIMITE");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE_WITH_TIMEOUT(assistant->phase(),QString("error"),15000);
        QCOMPARE(assistant->problem(),QString("limit"));
        QVERIFY(assistant->error().contains("Claude alcanzó su límite"));
        auto *other = visibleItem(window->contentItem(),"switchEngine");
        QVERIFY(other && other->isVisible());
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(!composer->property("active").toBool());
        QCOMPARE(assistant->phase(),QString("idle"));

        // Plan limits: Claude's arrive with each request, Codex's from its app-server.
        const auto claudePlan = assistant->limits()->claude();
        QCOMPARE(claudePlan["fiveHour"].toMap()["used"].toInt(),8);
        QCOMPARE(claudePlan["weekly"].toMap()["used"].toInt(),37);
        QCOMPARE(claudePlan["fiveHour"].toMap()["resetsAt"].toLongLong(),1795128828000LL);
        QTRY_COMPARE_WITH_TIMEOUT(assistant->limits()->codex()["weekly"].toMap()["used"].toInt(),26,15000);
        QCOMPARE(assistant->limits()->codex()["plan"].toString(),QString("plus"));
        QCOMPARE(assistant->limits()->codex()["credits"].toMap()["balance"].toString(),QString("0"));

        // The sidebar button: blue ring, diamond in Claude's colour, limits on hover, Uso on click.
        auto *usageButton = visibleItem(window->contentItem(),"usageButton");
        QVERIFY(usageButton && usageButton->isVisible());
        auto *diamond = visibleItem(usageButton,"usageDiamond");
        QCOMPARE(diamond->property("color").value<QColor>(),QColor("#d4714f"));
        // The rhombus sits in the exact middle of the ring, on a whole pixel.
        const QPointF diamondCenter = diamond->mapToScene(QPointF(diamond->width()/2,diamond->height()/2));
        QCOMPARE(diamondCenter,usageButton->mapToScene(QPointF(usageButton->width()/2,usageButton->height()/2)));
        QCOMPARE(diamondCenter,QPointF(std::round(diamondCenter.x()),std::round(diamondCenter.y())));
        const QPoint ringCenter = usageButton->mapToScene(QPointF(usageButton->width()/2,usageButton->height()/2)).toPoint();
        QTest::mouseMove(window,ringCenter);
        auto *usageCard = usageButton->findChild<QObject *>("usageCard");
        QVERIFY(usageCard);
        QTRY_VERIFY(usageCard->property("opened").toBool());
        capture("uso-boton");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,ringCenter);
        QTRY_COMPARE(js("workspaceTabs.currentIndex").toInt(),2);
        QTRY_VERIFY(!usageCard->property("opened").toBool());

        // The Uso tab shows what each request spent.
        js("workspaceTabs.currentIndex = 2");
        auto *usagePage = window->findChild<QQuickItem *>("usagePage");
        QVERIFY(usagePage);
        QTRY_VERIFY(usagePage->isVisible());
        QVERIFY(js("settingsShown").toBool());
        capture("uso");
        js("workspaceTabs.currentIndex = 0");
        assistant->setEngine("codex");
        QVERIFY(window->close());
    }
    void notionKeysFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("teclas.sqlite3"));
        const QString id = store.call("create_page",{{"title","Teclas"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Hola mundo"},{"spans",QJsonArray{Obj{{"start",5},{"end",10},{"style",1}}}}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto key = [&](Qt::Key k) { QTest::keyClick(window,k); };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(250);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto row = [&](int i) { return qvariant_cast<QQuickItem *>(js(QString("blockRepeater.itemAt(%1)").arg(i))); };

        // Enter splits at the cursor and the styled tail moves with it; Backspace at the start joins them back.
        js("blockRepeater.itemAt(0).focusAt(4)");
        key(Qt::Key_Return);
        QTRY_COMPARE(js("blocks.count").toInt(),2);
        QCOMPARE(js("blocks.get(0).body").toString(),QString("Hola"));
        QCOMPARE(js("blocks.get(1).body").toString(),QString(" mundo"));
        QCOMPARE(js("blocks.get(1).spans").toString(),QString(R"([{"end":6,"start":1,"style":1}])"));
        QTRY_VERIFY(js("blockRepeater.itemAt(1).editor.activeFocus").toBool());
        key(Qt::Key_Backspace);
        QTRY_COMPARE(js("blocks.count").toInt(),1);
        QCOMPARE(js("blocks.get(0).body").toString(),QString("Hola mundo"));
        QCOMPARE(js("blocks.get(0).spans").toString(),QString(R"([{"end":10,"start":5,"style":1}])"));
        QTRY_COMPARE(js("blockRepeater.itemAt(0).editor.cursorPosition").toInt(),4);

        // "- " starts a list, Enter continues it, Enter on an empty item leaves it.
        js("blockRepeater.itemAt(0).focusAt(-1)");
        key(Qt::Key_Return);
        QTRY_COMPARE(js("blocks.count").toInt(),2);
        QTRY_VERIFY(js("blockRepeater.itemAt(1).editor.activeFocus").toBool());
        type("- uno");
        QTRY_COMPARE(js("blocks.get(1).kind").toString(),QString("list"));
        QCOMPARE(js("blocks.get(1).body").toString(),QString("uno"));
        key(Qt::Key_Return);
        QTRY_COMPARE(js("blocks.count").toInt(),3);
        QCOMPARE(js("blocks.get(2).kind").toString(),QString("list"));
        QTRY_VERIFY(js("blockRepeater.itemAt(2).editor.activeFocus").toBool());
        key(Qt::Key_Return);
        QTRY_COMPARE(js("blocks.get(2).kind").toString(),QString("paragraph"));
        QCOMPARE(js("blocks.count").toInt(),3);

        // "/" opens the block menu; typing filters it (without accents) and Enter converts the line.
        type("/enc");
        auto *slash = window->findChild<QQuickItem *>("slashMenu");
        QVERIFY(slash);
        QTRY_VERIFY(slash->isVisible());
        QCOMPARE(slash->property("query").toString(),QString("enc"));
        QCOMPARE(js("slashMenu.matches.length").toInt(),3);
        capture("menu-barra");
        key(Qt::Key_Return);
        QTRY_VERIFY(!slash->isVisible());
        QCOMPARE(js("blocks.get(2).kind").toString(),QString("heading"));
        QCOMPARE(js("blocks.get(2).body").toString(),QString());

        // Inline Markdown: **clave** turns bold when the closing marks are typed.
        type("Plan **clave**");
        QTRY_COMPARE(js("blocks.get(2).body").toString(),QString("Plan clave"));
        QCOMPARE(js("blocks.get(2).spans").toString(),QString(R"([{"end":10,"start":5,"style":1}])"));
        key(Qt::Key_Up);
        QTRY_VERIFY(js("blockRepeater.itemAt(1).editor.activeFocus").toBool());

        // Drag the heading above everything by its ⋮⋮ handle.
        auto *handle = visibleItem(row(2),"blockHandle");
        QVERIFY(handle);
        const QPoint from = handle->mapToScene(QPointF(handle->width()/2,handle->height()/2)).toPoint();
        const QPoint to = row(0)->mapToScene(QPointF(20,2)).toPoint();
        QTest::mouseMove(window,from);
        QTest::mousePress(window,Qt::LeftButton,Qt::NoModifier,from);
        for (int step = 1; step <= 8; ++step) QTest::mouseMove(window,from+(to-from)*step/8);
        QTRY_VERIFY(js("dropAt === 0").toBool());
        capture("arrastrar");
        QTest::mouseRelease(window,Qt::LeftButton,Qt::NoModifier,to);
        QTRY_COMPARE(js("blocks.get(0).kind").toString(),QString("heading"));
        QCOMPARE(js("blocks.get(1).body").toString(),QString("Hola mundo"));

        // "+" adds a line below with the "/" menu already open.
        auto *add = visibleItem(row(1),"blockAdd");
        QVERIFY(add);
        QTest::mouseMove(window,add->mapToScene(QPointF(add->width()/2,add->height()/2)).toPoint());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,add->mapToScene(QPointF(add->width()/2,add->height()/2)).toPoint());
        QTRY_VERIFY(slash->isVisible());
        type("tar");
        key(Qt::Key_Return);
        QTRY_COMPARE(js("blocks.get(2).kind").toString(),QString("task"));
        QCOMPARE(js("blocks.get(2).body").toString(),QString());

        QVERIFY(js("flush()").toBool());
        QStringList kinds;
        for (const auto &b : store.page(id)["blocks"].toArray()) kinds << b.toObject()["type"].toString();
        QCOMPARE(kinds,(QStringList{"heading","paragraph","task","list"}));
        QVERIFY(window->close());
    }
    void blocksFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("bloques.sqlite3"));
        const QString id = store.call("create_page",{{"title","Bloques"},{"blocks",QJsonArray{
            Obj{{"type","heading"},{"text","Plan"},{"level",2}},
            Obj{{"type","numbered"},{"text","Idea"}},
            Obj{{"type","numbered"},{"text","Prototipo"}},
            Obj{{"type","numbered"},{"text","Detalle"},{"indent",1}},
            Obj{{"type","numbered"},{"text","Pruebas"}},
            Obj{{"type","toggle"},{"text","Notas"},{"collapsed",true}},
            Obj{{"type","paragraph"},{"text","Oculto dentro"},{"indent",1}},
            Obj{{"type","quote"},{"text","Jugar es aprender"}},
            Obj{{"type","callout"},{"text","Guarda copias"},{"icon","⚠️"}},
            Obj{{"type","code"},{"text","x = 1"}},
            Obj{{"type","divider"},{"text",""}},
            Obj{{"type","paragraph"},{"text",""}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto row = [&](int i) { return qvariant_cast<QQuickItem *>(js(QString("blockRepeater.itemAt(%1)").arg(i))); };
        QTRY_COMPARE(js("blocks.count").toInt(),12);

        // Numbered lists count per level; a closed toggle hides what it holds.
        QCOMPARE(row(1)->property("number").toInt(),1);
        QCOMPARE(row(2)->property("number").toInt(),2);
        QCOMPARE(row(3)->property("number").toInt(),1);
        QCOMPARE(row(4)->property("number").toInt(),3);
        QVERIFY(!row(6)->isVisible());
        QCOMPARE(row(0)->property("level").toInt(),2);
        capture("bloques");
        auto *arrow = visibleItem(row(5),"toggleArrow");
        QVERIFY(arrow && arrow->isVisible());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,arrow->mapToScene(QPointF(arrow->width()/2,arrow->height()/2)).toPoint());
        QTRY_VERIFY(row(6)->isVisible());
        QCOMPARE(js("blocks.get(5).collapsed").toBool(),false);

        // Tab nests under the line above (one level at most), Shift+Tab undoes it.
        js("blockRepeater.itemAt(4).focusAt(-1)");
        QTest::keyClick(window,Qt::Key_Tab);
        QTRY_COMPARE(js("blocks.get(4).indent").toInt(),1);
        QTRY_COMPARE(row(4)->property("number").toInt(),2);
        QTest::keyClick(window,Qt::Key_Tab);
        QCOMPARE(js("blocks.get(4).indent").toInt(),2);
        QTest::keyClick(window,Qt::Key_Tab);
        QCOMPARE(js("blocks.get(4).indent").toInt(),2);
        QTest::keyClick(window,Qt::Key_Backtab);
        QTest::keyClick(window,Qt::Key_Backtab);
        QTRY_COMPARE(js("blocks.get(4).indent").toInt(),0);

        // In code, Enter is a new line; Ctrl+Enter leaves the block.
        js("blockRepeater.itemAt(9).focusAt(-1)");
        QTest::keyClick(window,Qt::Key_Return);
        type("y");
        QTRY_COMPARE(js("blocks.get(9).body").toString(),QString("x = 1\ny"));
        QTest::keyClick(window,Qt::Key_Return,Qt::ControlModifier);
        QTRY_COMPARE(js("blocks.get(10).kind").toString(),QString("paragraph"));
        QCOMPARE(js("blocks.count").toInt(),13);

        // Markdown at the start of a line: "1. ", "> " (toggle) and "---" (divider).
        type("1. Uno");
        QTRY_COMPARE(js("blocks.get(10).kind").toString(),QString("numbered"));
        QCOMPARE(js("blocks.get(10).body").toString(),QString("Uno"));
        QTest::keyClick(window,Qt::Key_Return);
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(js("blocks.get(11).kind").toString(),QString("paragraph"));
        type("> Mas");
        QTRY_COMPARE(js("blocks.get(11).kind").toString(),QString("toggle"));
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(js("blocks.get(12).indent").toInt(),1);
        QTest::keyClick(window,Qt::Key_Backspace);
        QTRY_COMPARE(js("blocks.get(12).indent").toInt(),0);
        type("---");
        QTRY_COMPARE(js("blocks.get(12).kind").toString(),QString("divider"));

        // Page icon and cover.
        js("setPageIcon('🎮')");
        QTRY_COMPARE(js("pageIcon").toString(),QString("🎮"));
        js("setPageCover('gradient:bosque')");
        QTRY_COMPARE(js("pageCover").toString(),QString("gradient:bosque"));
        auto *cover = window->findChild<QQuickItem *>("pageCover");
        QVERIFY(cover && cover->isVisible());
        const auto saved = store.page(id);
        QCOMPARE(saved["icon"].toString(),QString("🎮"));
        QCOMPARE(saved["cover"].toString(),QString("gradient:bosque"));
        capture("portada");

        const auto blocks = saved["blocks"].toArray();
        QCOMPARE(blocks[9].toObject()["text"].toString(),QString("x = 1\ny"));
        QCOMPARE(blocks[8].toObject()["icon"].toString(),QString("⚠️"));
        QVERIFY(!blocks[5].toObject().contains("collapsed") || !blocks[5].toObject()["collapsed"].toBool());
        auto md = temp.filePath("bloques.md");
        QVERIFY(editor.run("export",{{"id",id},{"url",QUrl::fromLocalFile(md).toString()}})["ok"].toBool());
        QFile file(md);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QString text = QString::fromUtf8(file.readAll());
        for (const char *piece : {"# 🎮 Bloques","### Plan","1. Idea","2. Prototipo","    1. Detalle","3. Pruebas","▸ Notas","> Jugar es aprender","> ⚠️ Guarda copias","```\nx = 1\ny\n```","---"})
            QVERIFY2(text.contains(QString::fromUtf8(piece)),piece);
        QVERIFY(window->close());
    }
    void linksFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("enlaces.sqlite3"));
        const QString meetings = store.call("create_page",{{"title","Reuniones"},{"icon","📅"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Acuerdos"}}}}},"manual")["id"].toString();
        const QString diary = store.call("create_page",{{"title","Diario"},{"blocks",QJsonArray{Obj{{"type","paragraph"},{"text",""}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        js(QString("selectPage('%1')").arg(diary));
        QTRY_COMPARE(js("currentId").toString(),diary);

        // "@" searches pages without accents; Enter inserts the mention.
        js("blockRepeater.itemAt(0).focusEditor()");
        type("Ver @reu");
        auto *menu = window->findChild<QQuickItem *>("pageMenu");
        QVERIFY(menu);
        QTRY_VERIFY(menu->isVisible());
        QCOMPARE(js("mentionMenu.matches[0].title").toString(),QString("Reuniones"));
        capture("mencion");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_VERIFY(!menu->isVisible());
        QTRY_COMPARE(js("blocks.get(0).body").toString(),QString("Ver Reuniones "));
        const QString mention = "[{\"end\":13,\"link\":\"lunqio:" "//page/" + meetings + "\",\"start\":4,\"style\":0}]";
        QCOMPARE(js("blocks.get(0).spans").toString(),mention);

        // "[[" with a new name creates the page as a subpage and mentions it.
        type("y [[Ideas");
        QTRY_VERIFY(menu->isVisible());
        QTRY_VERIFY(js("mentionMenu.current().create === true").toBool());
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(js("blocks.get(0).body").toString(),QString("Ver Reuniones y Ideas "));
        QVERIFY(js("flush()").toBool());
        QString ideas;
        for (const auto &p : store.navigation()) if (p.toObject()["title"] == "Ideas") ideas = p.toObject()["id"].toString();
        QVERIFY(!ideas.isEmpty());
        QCOMPARE(store.page(ideas)["parent_id"].toString(),diary);
        QCOMPARE(store.backlinks(meetings).first().toObject()["title"].toString(),QString("Diario"));

        // A click on the mention opens the page, which lists where it is mentioned.
        auto *field = qvariant_cast<QQuickItem *>(js("blockRepeater.itemAt(0).editor"));
        QRectF chip;
        QMetaObject::invokeMethod(field,"positionToRectangle",Q_RETURN_ARG(QRectF,chip),Q_ARG(int,7));
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,field->mapToScene(QPointF(chip.x()+2,chip.y()+chip.height()/2)).toPoint());
        QTRY_COMPARE(js("currentId").toString(),meetings);
        QTRY_COMPARE(js("backlinks.length").toInt(),1);
        auto *toggle = window->findChild<QQuickItem *>("backlinksToggle");
        QVERIFY(toggle && toggle->isVisible());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,toggle->mapToScene(QPointF(toggle->width()/2,toggle->height()/2)).toPoint());
        QTRY_VERIFY(js("backlinksOpen").toBool());
        capture("referencias");
        QVERIFY(window->close());
    }
    void pastePhotoFlow() {
        // On a real desktop this would replace the user's clipboard.
        if (QGuiApplication::platformName() != "offscreen") QSKIP("Usa el portapapeles; ejecútala con -platform offscreen.");
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("pegar.sqlite3"));
        const QString page = store.call("create_page",{{"title","Capturas"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Antes"}},Obj{{"type","paragraph"},{"text","Despues"}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto kinds = [&] { return js("{ const k = []; for (let i = 0; i < blocks.count; ++i) k.push(blocks.get(i).kind); k.join(',') }").toString(); };
        auto paste = [&](int index) {
            js(QString("blockRepeater.itemAt(%1).focusEditor()").arg(index));
            QTest::qWait(50);
            QTest::keyClick(window,Qt::Key_V,Qt::ControlModifier);
        };
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);
        auto *clip = QGuiApplication::clipboard();
        QImage shot(320,180,QImage::Format_RGB32);
        shot.fill(QColor("#F32201"));

        // A screenshot becomes a photo block under the block being edited, not a link.
        clip->setImage(shot);
        QTRY_VERIFY(editor.clipboardPhoto());
        paste(0);
        QTRY_COMPARE(kinds(),QString("paragraph,image,paragraph"));
        QCOMPARE(js("blocks.get(0).body").toString(),QString("Antes"));
        QCOMPARE(js("blocks.get(2).body").toString(),QString("Despues"));
        QCOMPARE(js("blocks.get(1).asset").toString().size(),64);
        QVERIFY(js("flush()").toBool());
        QCOMPARE(store.page(page)["blocks"].toArray()[1].toObject()["type"].toString(),QString("image"));

        // "Copiar imagen" in a browser adds the address and an <img> tag: still a photo.
        auto *browser = new QMimeData;
        browser->setImageData(shot);
        browser->setText("https://example.com/foto.png");
        browser->setHtml("<img src=\"https://example.com/foto.png\">");
        clip->setMimeData(browser);
        QTRY_VERIFY(editor.clipboardPhoto());
        paste(2);
        QTRY_COMPARE(kinds(),QString("paragraph,image,paragraph,image,paragraph"));
        QCOMPARE(js("blocks.get(4).body").toString(),QString());
        QTRY_COMPARE(js("editIndex").toInt(),4);

        // Word copies the text together with a picture of it: that pastes as text.
        auto *word = new QMimeData;
        word->setImageData(shot);
        word->setText("Texto de Word");
        word->setHtml("<p>Texto de Word</p>");
        clip->setMimeData(word);
        QTRY_VERIFY(!editor.clipboardPhoto());
        paste(4);
        QTRY_COMPARE(js("blocks.get(4).body").toString(),QString("Texto de Word"));
        QCOMPARE(kinds(),QString("paragraph,image,paragraph,image,paragraph"));

        // An image file copied in Explorer keeps its name as the caption; an empty paragraph turns into it.
        const QString file = temp.filePath("Diagrama.png");
        QVERIFY(shot.save(file));
        js("insertBlock(5,'paragraph','','[]',0)");
        QTRY_COMPARE(js("blocks.count").toInt(),6);
        auto *files = new QMimeData;
        files->setUrls({QUrl::fromLocalFile(file)});
        clip->setMimeData(files);
        QTRY_VERIFY(editor.clipboardPhoto());
        paste(5);
        QTRY_COMPARE(kinds(),QString("paragraph,image,paragraph,image,paragraph,image,paragraph"));
        QCOMPARE(js("blocks.get(5).body").toString(),QString("Diagrama"));
        QVERIFY(js("flush()").toBool());
        QCOMPARE(store.page(page)["blocks"].toArray().size(),7);
        js("pageScroll.contentItem.contentY = 0");
        capture("pegar-foto");
        clip->clear();
        QVERIFY(window->close());
    }
    void lookFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("aspecto.sqlite3"));
        const QString page = store.call("create_page",{{"title","Aspecto"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Texto de prueba para dar color"}},Obj{{"type","paragraph"},{"text","Segundo"}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1400,900);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);

        // Text colour and background on a selection, kept in the spans and drawn in the theme's tones.
        js("blockRepeater.itemAt(0).focusAt(0); blockRepeater.itemAt(0).editor.select(9,15)");
        js("blockRepeater.itemAt(0).formatter.setColor('blue'); blockRepeater.itemAt(0).formatter.setBackground('yellow')");
        QTRY_COMPARE(js("JSON.stringify(draft()[0].spans)").toString(),QString("[{\"background\":\"yellow\",\"color\":\"blue\",\"end\":15,\"start\":9,\"style\":0}]"));
        auto *field = qvariant_cast<QQuickItem *>(js("blockRepeater.itemAt(0).editor"));
        QTextCursor cursor(qvariant_cast<QQuickTextDocument *>(field->property("textDocument"))->textDocument());
        cursor.setPosition(11);
        QCOMPARE(cursor.charFormat().foreground().color(),js("Theme.tones.blue[0]").value<QColor>());
        QCOMPARE(js("blockRepeater.itemAt(0).formatter.activeColor").toString(),QString("blue"));

        // The block's alignment and background, each one undo step away.
        js("setBlockLook(1,'align','center'); structureMarked = false; setBlockLook(1,'fill','green')");
        QCOMPARE(js("draft()[1].align").toString(),QString("center"));
        QCOMPARE(js("draft()[1].background").toString(),QString("green"));
        QCOMPARE(js("blockRepeater.itemAt(1).editor.horizontalAlignment").toInt(),int(Qt::AlignHCenter));
        js("blockRepeater.itemAt(1).focusAt(0)");
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QTRY_VERIFY(!js("draft()[1].background").isValid());
        QCOMPARE(js("draft()[1].align").toString(),QString("center"));
        QTest::keyClick(window,Qt::Key_Y,Qt::ControlModifier);
        QTRY_COMPARE(js("draft()[1].background").toString(),QString("green"));

        // Enter splits a block; Ctrl+Z puts it back together.
        js("blockRepeater.itemAt(0).focusAt(5)");
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE(js("blocks.count").toInt(),3);
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QTRY_COMPARE(js("blocks.count").toInt(),2);
        QCOMPARE(js("draft()[0].text").toString(),QString("Texto de prueba para dar color"));
        QVERIFY(js("flush()").toBool());
        // Backspace joins the blocks; one Ctrl+Z brings both back, even after the join was saved.
        js("blockRepeater.itemAt(1).focusAt(0)");
        QTest::keyClick(window,Qt::Key_Backspace);
        QTRY_COMPARE(js("blocks.count").toInt(),1);
        QVERIFY(js("flush()").toBool());
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QTRY_COMPARE(js("blocks.count").toInt(),2);
        QCOMPARE(js("draft()[1].text").toString(),QString("Segundo"));
        QCOMPARE(js("draft()[1].background").toString(),QString("green"));
        QVERIFY(js("flush()").toBool());

        // The page's font, smaller text and full width, saved with the page.
        js("setPageLook('font','serif')");
        QTRY_COMPARE(store.page(page)["font"].toString(),QString("serif"));
        QCOMPARE(js("blockRepeater.itemAt(0).editor.font.family").toString(),QString("Georgia"));
        js("setPageLook('small_text',true)");
        QTRY_COMPARE(js("blockRepeater.itemAt(0).editor.font.pixelSize").toInt(),14);
        const double narrow = js("pageColumn.width").toDouble();
        js("setPageLook('full_width',true)");
        QTRY_VERIFY(js("pageColumn.width").toDouble() > narrow);
        QVERIFY(store.page(page)["full_width"].toBool() && store.page(page)["small_text"].toBool());

        // A photo: centred, with rounded corners and a border, saved and exported with that look.
        QImage sample(200,100,QImage::Format_RGB32);
        sample.fill(QColor("#A82E13"));
        const QString file = temp.filePath("Muestra.png");
        QVERIFY(sample.save(file));
        engine.rootContext()->setContextProperty("sampleUrl",QUrl::fromLocalFile(file));
        QVERIFY(js("insertPhotoFiles([sampleUrl],1)").toBool());
        QTRY_COMPARE(js("draft()[2].type").toString(),QString("image"));
        js("setBlockLook(2,'align','center'); structureMarked = false; setBlockLook(2,'frame','rounded'); structureMarked = false; blocks.setProperty(2,'photoPercent',50); markDirty()");
        QVERIFY(js("flush()").toBool());
        const auto stored = store.page(page)["blocks"].toArray()[2].toObject();
        QCOMPARE(stored["align"].toString(),QString("center"));
        QCOMPARE(stored["frame"].toString(),QString("rounded"));
        auto *photo = visibleItem(window->contentItem(),"pagePhoto");
        QVERIFY(photo);
        QTRY_COMPARE(photo->property("radius").toDouble(),12.0);
        QTRY_VERIFY(photo->x() > 50);
        capture("aspecto");
        const QString html = temp.filePath("aspecto.html");
        QVERIFY(editor.run("export",{{"id",page},{"url",QUrl::fromLocalFile(html).toString()}})["ok"].toBool());
        QFile exported(html);
        QVERIFY(exported.open(QIODevice::ReadOnly));
        const QByteArray data = exported.readAll();
        for (const char *piece : {"color:#2f6fa3;background-color:#fbf1d3","text-align:center;background-color:#e6f1e8","border-radius:12px","<figure style=\"text-align:center\">"})
            QVERIFY2(data.contains(piece),piece);
        QVERIFY(window->close());
    }
    void pagesMenuFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("menu.sqlite3"));
        auto make = [&](const QString &title, const QJsonValue &parent, const QJsonArray &blocks) {
            return store.call("create_page",{{"title",title},{"parent_id",parent},{"blocks",blocks}},"manual")["id"].toString();
        };
        const QString course = make("Curso",QJsonValue::Null,{Obj{{"type","paragraph"},{"text","Índice"}}});
        const QString unit = make("Unidad 1",course,{Obj{{"type","paragraph"},{"text","Temas"}}});
        const QString lesson = make("Lección",unit,{
            Obj{{"type","heading"},{"text","Objetivos"},{"level",1}},Obj{{"type","paragraph"},{"text","Aprender"}},
            Obj{{"type","heading"},{"text","Actividades"},{"level",2}},Obj{{"type","paragraph"},{"text","Practicar"},
                {"spans",QJsonArray{Obj{{"start",0},{"end",9},{"style",0},{"comment","Revisar"}}}}}});
        const QString notes = make("Notas sueltas",QJsonValue::Null,{Obj{{"type","paragraph"},{"text","Nada"}}});
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1400,880);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto find = [&](const QString &name) {
            QQuickItem *item = nullptr;
            [&] { QTRY_VERIFY((item = visibleItem(window->contentItem(),name)) && item->isVisible() && item->width() > 0); }();
            return item;
        };
        auto centre = [](QQuickItem *it) { return it->mapToScene(it->boundingRect().center()).toPoint(); };

        // Breadcrumbs above the title, and the outline of its headings at the right.
        js("collapsed = {}; refreshNavigation()");
        js(QString("selectPage('%1')").arg(lesson));
        QTRY_COMPARE(js("ancestors.map(p => p.title).join(' / ')").toString(),QString("Curso / Unidad 1"));
        QCOMPARE(js("headings.length").toInt(),2);
        auto *outline = find("pageOutline");
        QTest::mouseMove(window,centre(outline));
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find(QString("outline-2"))));
        QTRY_COMPARE(js("editIndex").toInt(),2);

        // Ctrl+D copies the block below it, without its comment.
        js("blockRepeater.itemAt(3).focusAt(0)");
        QTest::keyClick(window,Qt::Key_D,Qt::ControlModifier);
        QTRY_COMPARE(js("blocks.count").toInt(),5);
        QCOMPARE(js("draft()[4].text").toString(),QString("Practicar"));
        QVERIFY(!js("draft()[4].spans").isValid());
        QVERIFY(js("flush()").toBool());

        // Right click on a page of the sidebar: send it to the trash, then Deshacer.
        js("sidebar.rowMenu.show('" + notes + "')");
        QTRY_VERIFY(js("sidebar.rowMenu.opened").toBool());
        capture("menu-pagina");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("rowTrash")));
        QTRY_VERIFY(!store.page(notes)["deleted_at"].isNull());
        QTRY_VERIFY(find("toast")->isVisible());
        QCOMPARE(js("currentId").toString(),lesson);
        capture("papelera-deshacer");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("toastAction")));
        QTRY_VERIFY(store.page(notes)["deleted_at"].isNull());
        // Trashing the open page shows another one.
        QVERIFY(js(QString("trashPage('%1')").arg(lesson)).toBool());
        QTRY_VERIFY(js("currentId").toString() != lesson);
        QVERIFY(js(QString("restorePage('%1')").arg(lesson)).toBool());

        // Duplicate, rename and move.
        const QString copy = js(QString("duplicatePage('%1')").arg(lesson)).toString();
        QVERIFY2(!copy.isEmpty(),qPrintable(js("notice").toString()+" "+QString::fromUtf8(QJsonDocument(store.page(lesson)).toJson(QJsonDocument::Compact))));
        QCOMPARE(store.page(copy)["title"].toString(),QString::fromUtf8("Lección (copia)"));
        QCOMPARE(store.page(copy)["parent_id"].toString(),unit);
        QCOMPARE(store.page(copy)["blocks"].toArray().size(),5);
        QVERIFY(!store.page(copy)["blocks"].toArray()[3].toObject().contains("spans"));
        QVERIFY(js(QString("renamePage('%1','Notas del curso')").arg(notes)).toBool());
        QCOMPARE(store.page(notes)["title"].toString(),QString("Notas del curso"));
        QVERIFY(js(QString("movePage('%1','%2')").arg(notes,course)).toBool());
        QCOMPARE(store.page(notes)["parent_id"].toString(),course);
        // The move dialog never offers the page itself or the pages inside it.
        js(QString("moveDialog.pageId = '%1'").arg(course));
        QCOMPARE(js(QString("moveDialog.targets.some(p => p.id === '%1' || p.id === '%2' || p.id === '%3')").arg(course,unit,lesson)).toBool(),false);
        QVERIFY(window->close());
    }
    void askFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("preguntar.sqlite3"));
        const QString trip = store.call("create_page",{{"title","Viaje a Oaxaca"},{"blocks",QJsonArray{
            Obj{{"type","task"},{"text","Comprar boletos para el viaje"},{"checked",false}},
            Obj{{"type","task"},{"text","Reservar hotel"},{"checked",true}}}}},"manual")["id"].toString();
        const QString recipes = store.call("create_page",{{"title","Recetas"},{"blocks",QJsonArray{
            Obj{{"type","paragraph"},{"text","Mole negro con chocolate de la abuela."}}}}},"manual")["id"].toString();
        // The notes sent with a question: matching words without accents; tasks gather the unfinished ones.
        const auto mole = store.notesFor(QString::fromUtf8("¿Cómo se hace el mole?"),{});
        QCOMPARE(mole.first().toObject()["id"].toString(),recipes);
        const auto tasks = store.notesFor(QString::fromUtf8("¿Qué tareas tengo pendientes?"),recipes);
        QCOMPARE(tasks.first().toObject()["id"].toString(),recipes);
        QCOMPARE(tasks.last().toObject()["id"].toString(),QString("tareas-sin-terminar"));
        QVERIFY(tasks.last().toObject()["text"].toString().contains("Comprar boletos para el viaje (Viaje a Oaxaca)"));
        QVERIFY(!tasks.last().toObject()["text"].toString().contains("Reservar hotel"));

        const QString fake = QCoreApplication::applicationFilePath();
        Editor editor(store,fake,fake);
        auto *assistant = editor.assistant();
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1300,860);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        assistant->setEngine("claude");
        QTRY_COMPARE(assistant->claudeAccount(),QString("in"));
        // From Inicio (no page open), so only the gathered tasks go with the question.
        js("browseTrash(false)");
        QTRY_COMPARE(js("currentId").toString(),QString());
        js("openAsk()");
        QTRY_COMPARE(js("workspaceTabs.currentIndex").toInt(),3);
        auto *field = visibleItem(window->contentItem(),"askField");
        QVERIFY(field);
        field->forceActiveFocus();
        for (QChar c : QString("Que tareas tengo pendientes?")) QTest::keyClick(window,c.toLatin1());
        QTest::keyClick(window,Qt::Key_Return);
        QTRY_COMPARE_WITH_TIMEOUT(assistant->conversation().size(),1,15000);
        const QVariantMap turn = assistant->conversation().first().toMap();
        QCOMPARE(turn["answer"].toString(),QString("Te falta:\n- Comprar boletos para el viaje"));
        // Only notes it was given count as sources.
        const QVariantList sources = turn["sources"].toList();
        QCOMPARE(sources.size(),1);
        QCOMPARE(sources.first().toMap()["id"].toString(),QString("tareas-sin-terminar"));
        QCOMPARE(assistant->usage()->property("count").toInt() > 0,true);
        capture("preguntar");
        // The answer kept as a page: a list item and no link for the gathered tasks.
        js("askPage.keep(backend.assistant.conversation[0])");
        QTRY_COMPARE(js("titleInput.text").toString(),QString("Que tareas tengo pendientes?"));
        QCOMPARE(js("draft()[1].type").toString(),QString("list"));
        QCOMPARE(js("draft()[1].text").toString(),QString("Comprar boletos para el viaje"));
        Q_UNUSED(trip);
        QVERIFY(window->close());
    }
    void templatesFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("plantillas.sqlite3"));
        const QString source = store.call("create_page",{{"title","Sprint"},{"icon","🏁"},{"font","serif"},{"blocks",QJsonArray{
            Obj{{"type","heading"},{"text","Objetivo"},{"level",2}},
            Obj{{"type","paragraph"},{"text","Revisar con el equipo"},{"spans",QJsonArray{
                Obj{{"start",0},{"end",7},{"style",1}},Obj{{"start",8},{"end",11},{"style",0},{"comment","¿Quién?"}}}}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1300,860);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto click = [&](const QString &name) {
            QQuickItem *item = nullptr;
            [&] { QTRY_VERIFY((item = visibleItem(window->contentItem(),name)) && item->isVisible() && item->width() > 0); }();
            QVERIFY(item);
            QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,item->mapToScene(item->boundingRect().center()).toPoint());
        };
        // A new page is empty, so it offers the templates under its title.
        js("newPage(null)");
        QTRY_VERIFY(js("pageEmpty").toBool());
        QVERIFY(visibleItem(window->contentItem(),"templateStrip")->isVisible());
        capture("plantillas");
        click("template-0");
        const QString meeting = js("currentId").toString();
        QTRY_COMPARE(store.page(meeting)["icon"].toString(),QString("📋"));
        QCOMPARE(store.page(meeting)["title"].toString(),"Reunión · "+js("today()").toString());
        QCOMPARE(store.page(meeting)["blocks"].toArray().size(),8);
        QCOMPARE(store.page(meeting)["blocks"].toArray()[0].toObject()["text"].toString(),QString("Asistentes"));
        QVERIFY(!js("pageEmpty").toBool());

        // Your own template: a copy of a page without its comments, offered next to Flowen's.
        js(QString("selectPage('%1')").arg(source));
        QTRY_COMPARE(js("currentId").toString(),source);
        QVERIFY(js("saveTemplate('Sprint semanal')").toBool());
        QCOMPARE(store.templates().size(),1);
        const auto copied = store.templates()[0].toObject()["page"].toObject();
        QCOMPARE(copied["font"].toString(),QString("serif"));
        QCOMPARE(QJsonDocument(copied["blocks"].toArray()[1].toObject()["spans"].toArray()).toJson(QJsonDocument::Compact),
                 QByteArray(R"([{"end":7,"start":0,"style":1}])"));
        js("newPage(null)");
        QTRY_VERIFY(js("pageEmpty").toBool());
        click("template-6");
        const QString sprint = js("currentId").toString();
        QTRY_COMPARE(store.page(sprint)["icon"].toString(),QString("🏁"));
        QCOMPARE(store.page(sprint)["title"].toString(),QString("Sprint"));
        QCOMPARE(store.page(sprint)["font"].toString(),QString("serif"));
        QCOMPARE(store.page(sprint)["blocks"].toArray()[1].toObject()["text"].toString(),QString("Revisar con el equipo"));
        // Ctrl+Z on the page takes the template back out.
        js("blockRepeater.itemAt(0).focusAt(0)");
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QTRY_VERIFY(js("pageEmpty").toBool());
        js("removeTemplate(userTemplates[0].id)");
        QTRY_COMPARE(js("userTemplates.length").toInt(),0);
        QCOMPARE(store.templates().size(),0);
        QVERIFY(window->close());
    }
    void themeFlow() {
        // FLOWEN_THEME forces a theme for previews; this test checks the saved preference instead.
        const QByteArray forced = qgetenv("FLOWEN_THEME");
        qunsetenv("FLOWEN_THEME");
        auto restoreEnv = qScopeGuard([&] { if (!forced.isEmpty()) qputenv("FLOWEN_THEME",forced); });
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("tema.sqlite3"));
        auto make = [&](const QString &title, const QString &icon, const QJsonArray &blocks) {
            return store.call("create_page",{{"title",title},{"icon",icon},{"blocks",blocks}},"manual")["id"].toString();
        };
        const QString meetings = make("Reuniones","📅",{Obj{{"type","paragraph"},{"text","Acuerdos"}}});
        make("Ideas","💡",{Obj{{"type","paragraph"},{"text","Por ordenar"}}});
        // A page that shows every kind of block, for the previews of each look.
        const QString intro = QString::fromUtf8("Las páginas reúnen las ideas del equipo. Consulta la guía de identidad y las notas de Reuniones.");
        auto span = [&](const QString &piece, Obj extra) {
            const int at = int(intro.indexOf(QString::fromUtf8(piece.toUtf8())));
            extra["start"] = at; extra["end"] = at+int(piece.size());
            if (!extra.contains("style")) extra["style"] = 0;
            return extra;
        };
        const int linkAt = int(intro.indexOf(QString::fromUtf8("guía")))+2;
        const QString page = make(QString::fromUtf8("Notas de diseño"),"📓",{
            Obj{{"type","paragraph"},{"text",intro},{"spans",QJsonArray{span("ideas del equipo",{{"style",1}}),
                span(QString::fromUtf8("guía de identidad"),{{"link","https://ejemplo.com/guia"}}),
                span("Reuniones",{{"link","lunqio:" "//page/"+meetings}})}}},
            Obj{{"type","heading"},{"text",QString::fromUtf8("Plan de la sesión")},{"level",2}},
            Obj{{"type","list"},{"text","Revisar la paleta en cada vista"}},
            Obj{{"type","list"},{"text",QString::fromUtf8("Probar los íconos a 16, 20 y 24 px")}},
            Obj{{"type","task"},{"text","Preparar la demo"},{"checked",false}},
            Obj{{"type","task"},{"text","Enviar las notas"},{"checked",true}},
            Obj{{"type","quote"},{"text",QString::fromUtf8("Escribir, comentar y revisar en un solo lugar.")}},
            Obj{{"type","callout"},{"text",QString::fromUtf8("Cambia la vista en Ver → Tema o con Ctrl+Shift+L.")},{"icon","💡"}},
            Obj{{"type","code"},{"text","tema = \"flowen\""}}});
        store.setFavorite(page,true);
        Editor editor(store,QCoreApplication::applicationFilePath());
        editor.setTheme("dark");
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1400,900);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        // The link's colour in the first block, as the editor draws it.
        auto linkInk = [&] {
            auto *field = qvariant_cast<QQuickItem *>(js("blockRepeater.itemAt(0).editor"));
            auto *document = qvariant_cast<QQuickTextDocument *>(field->property("textDocument"));
            QTextCursor cursor(document->textDocument());
            cursor.setPosition(linkAt);
            return cursor.charFormat().foreground().color();
        };
        auto saved = [] { return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Flowen","Editor").value("theme").toString(); };
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);

        // Flowen oscuro, the identity, by default.
        QCOMPARE(window->color(),QColor("#231B19"));
        QCOMPARE(linkInk(),QColor("#FF7959"));
        QCOMPARE(js("Theme.glyphAccent").value<QColor>(),QColor("#FF7959"));
        capture("editor-flowen-oscuro");
        // Flowen claro, from Ver → Tema, saved for the next start. Switching does not edit the page.
        editor.setTheme("light");
        QTRY_COMPARE(window->color(),QColor("#FFF9F0"));
        QCOMPARE(saved(),QString("light"));
        QCOMPARE(linkInk(),QColor("#A82E13"));
        QCOMPARE(js("Theme.glyph").value<QColor>(),QColor("#2C1312"));
        capture("editor-flowen-claro");
        // The usual Claro and Oscuro: neutral white and black, a blue accent, one-colour symbols.
        editor.setTheme("white");
        QTRY_COMPARE(window->color(),QColor("#FFFFFF"));
        QCOMPARE(linkInk(),QColor("#1F6FD1"));
        QCOMPARE(js("Theme.glyphAccent").value<QColor>(),js("Theme.glyph").value<QColor>());
        capture("editor-claro");
        editor.setTheme("black");
        QTRY_COMPARE(window->color(),QColor("#191919"));
        QCOMPARE(linkInk(),QColor("#9DBDF0"));
        capture("editor-oscuro");
        QVERIFY(!js("dirty").toBool());

        // Ctrl+Shift+L flips between the light and dark version of the same look, as in Notion.
        QTest::keyClick(window,Qt::Key_L,Qt::ControlModifier|Qt::ShiftModifier);
        QTRY_COMPARE(editor.theme(),QString("white"));
        QTRY_COMPARE(window->color(),QColor("#FFFFFF"));
        editor.setTheme("light");
        QTRY_COMPARE(js("Theme.scheme").toString(),QString("light"));
        QTest::keyClick(window,Qt::Key_L,Qt::ControlModifier|Qt::ShiftModifier);
        QTRY_COMPARE(editor.theme(),QString("dark"));
        QTRY_COMPARE(window->color(),QColor("#231B19"));
        QCOMPARE(linkInk(),QColor("#FF7959"));
        // "Según Windows" uses the usual Claro or Oscuro, as Windows is.
        editor.setTheme("system");
        const bool systemDark = QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
        QTRY_COMPARE(js("Theme.scheme").toString(),QString(systemDark ? "black" : "white"));
        editor.setTheme("dark");
        QVERIFY(!js("dirty").toBool());
        QVERIFY(window->close());
    }
    void favoritesFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("favoritos.sqlite3"));
        auto make = [&](const QString &title, const QString &icon) {
            Obj args{{"title",title},{"blocks",QJsonArray{Obj{{"type","paragraph"},{"text",title+" en curso"}}}}};
            if (!icon.isEmpty()) args["icon"] = icon;
            return store.call("create_page",args,"manual")["id"].toString();
        };
        const QString plan = make("Plan","🗺️"), drafts = make("Notas",""), ideas = make("Ideas","💡");
        store.call("update_page",{{"id",plan},{"expected_revision",1},{"cover","gradient:aurora"}},"manual");

        // Favorites keep the chosen order and wait in the trash; visits never create revisions.
        store.setFavorite(drafts,true);
        store.setFavorite(plan,true,0);
        QCOMPARE(store.favorites(),(QJsonArray{plan,drafts}));
        const qint64 before = store.generation();
        store.visit(ideas);
        QCOMPARE(store.generation(),before);
        QCOMPARE(store.recent(8).first().toObject()["id"].toString(),ideas);
        store.call("trash_page",{{"id",drafts},{"expected_revision",1}},"manual");
        QCOMPARE(store.favorites(),(QJsonArray{plan}));
        QVERIFY(store.recent(8).size() == 1);
        store.setFavorite(ideas,true);
        store.call("restore_page",{{"id",drafts},{"expected_revision",2}},"manual");
        QCOMPARE(store.favorites(),(QJsonArray{plan,drafts,ideas}));
        store.setFavorite(ideas,false);
        QCOMPARE(store.favorites(),(QJsonArray{plan,drafts}));

        Editor editor(store,QCoreApplication::applicationFilePath());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1200,760);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto item = [&](const QString &name) {
            QQuickItem *found = nullptr;
            [&] { QTRY_VERIFY((found = visibleItem(window->contentItem(),name)) && found->isVisible() && found->width() > 0); }();
            return found;
        };
        auto center = [&](QQuickItem *it) { return it->mapToScene(it->boundingRect().center()).toPoint(); };
        auto titles = [&](const QString &list) { return js(list+".map(p => p.title).join(',')").toString(); };

        QCOMPARE(titles("favoriteRows"),QString("Plan,Notas"));
        QVERIFY(item("favorites")->isVisible());

        // The star next to the page options adds the open page at the end of Favoritos.
        js(QString("selectPage('%1')").arg(ideas));
        QTRY_COMPARE(js("currentId").toString(),ideas);
        QVERIFY(!js("isFavorite").toBool());
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,center(item("favoriteButton")));
        QTRY_VERIFY(js("isFavorite").toBool());
        QCOMPARE(titles("favoriteRows"),QString("Plan,Notas,Ideas"));

        // Dragging Ideas above Plan reorders the list, and the library keeps that order.
        auto *dragged = item("favorites-2");
        auto *top = item("favorites-0");
        QPoint at = center(dragged);
        const QPoint goal = top->mapToScene(QPointF(top->width()/2,4)).toPoint();
        QTest::mousePress(window,Qt::LeftButton,Qt::NoModifier,at);
        for (int i = 1; i <= 12; ++i) QTest::mouseMove(window,at+(goal-at)*i/12,15);
        QTest::mouseRelease(window,Qt::LeftButton,Qt::NoModifier,goal);
        QTRY_COMPARE(titles("favoriteRows"),QString("Ideas,Plan,Notas"));
        QCOMPARE(store.favorites().first().toString(),ideas);

        // Recientes lists visited pages, newest first; a click opens one.
        js(QString("selectPage('%1')").arg(plan));
        QTRY_COMPARE(js("recentRows[0].id").toString(),plan);
        QCOMPARE(js("recentRows[1].id").toString(),ideas);
        QCOMPARE(js("recentRows[0].detail").toString(),QString("ahora"));
        capture("favoritos");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,center(item("recent-1")));
        QTRY_COMPARE(js("currentId").toString(),ideas);
        QCOMPARE(js("ago(new Date(clock-3*3600000).toISOString(),false)").toString(),QString("hace 3 h"));

        // Removing the star takes the page out of Favoritos.
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,center(item("favoriteButton")));
        QTRY_COMPARE(titles("favoriteRows"),QString("Plan,Notas"));

        // Inicio shows the recent pages as cards.
        js("browseTrash(false)");
        QTRY_COMPARE(js("currentId").toString(),QString());
        item("recentCards");
        capture("inicio-recientes");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,center(item("recentCard-1")));
        QTRY_COMPARE(js("currentId").toString(),plan);
        QVERIFY(window->close());
    }
    void viewModesFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("vistas.sqlite3"));
        // A report long enough for several sheets: a heading every six blocks, paragraphs of 1 to 4 sentences.
        const QString sentence = QString::fromUtf8("El equipo revisó las notas de la semana y acordó los siguientes pasos para el informe. ");
        QJsonArray content;
        for (int i = 0; i < 36; ++i) {
            if (i % 6 == 0) content.append(Obj{{"type","heading"},{"text",QString::fromUtf8("Sección %1").arg(i/6+1)},{"level",2}});
            else content.append(Obj{{"type","paragraph"},{"text",sentence.repeated(1+i%4).trimmed()}});
        }
        content.append(Obj{{"type","task"},{"text","Enviar el informe"},{"checked",false}});
        const QString page = store.call("create_page",{{"title","Informe trimestral"},{"icon",QString::fromUtf8("📄")},
                                                       {"cover","gradient:aurora"},{"blocks",content}},"manual")["id"].toString();
        auto settings = [] { return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Flowen","Editor").value("ui/viewMode").toString(); };
        auto forget = qScopeGuard([] { QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Flowen","Editor").remove("ui"); });
        Editor editor(store,QCoreApplication::applicationFilePath());
        // The view is kept between sessions: this one starts in Modo lectura.
        editor.setPreference("viewMode","read");
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1400,900);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            // The pointer rests on the desk, so no button shows its tooltip in the picture.
            QTest::mouseMove(window,QPoint(window->width()-60,window->height()/2));
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto find = [&](const QString &name) {
            QQuickItem *item = nullptr;
            [&] { QTRY_VERIFY((item = visibleItem(window->contentItem(),name)) && item->isVisible() && item->width() > 0); }();
            return item;
        };
        auto type = [&](const QString &text) { for (QChar c : text) QTest::keyClick(window,c.toLatin1()); };
        auto shown = [&](const QString &name) { auto *item = visibleItem(window->contentItem(),name); return item && item->isVisible(); };
        auto centre = [](QQuickItem *it) { return it->mapToScene(it->boundingRect().center()).toPoint(); };
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);

        // Modo lectura: the page reads the same, nothing on it changes, and the tools give way to «Editar».
        QCOMPARE(js("viewMode").toString(),QString("read"));
        QVERIFY(!js("blockRepeater.itemAt(1).editable").toBool());
        QVERIFY(js("titleInput.readOnly").toBool());
        find("readingBar");
        QVERIFY(!shown("composeButton"));
        const QString before = js("blocks.get(1).body").toString();
        js("blockRepeater.itemAt(1).focusAt(0)");
        type("xyz");
        QTest::keyClick(window,Qt::Key_Return);
        QTest::keyClick(window,Qt::Key_Backspace);
        QTest::keyClick(window,Qt::Key_J,Qt::ControlModifier);
        QTest::qWait(100);
        QCOMPARE(js("blocks.get(1).body").toString(),before);
        QCOMPARE(js("blocks.count").toInt(),37);
        QVERIFY(!js("composer.visible").toBool());
        QVERIFY(!js("dirty").toBool());
        capture("vista-lectura");
        // A new page is for writing, so it opens in Edición.
        js("newPage(null)");
        QTRY_COMPARE(js("viewMode").toString(),QString("edit"));
        QVERIFY(js("titleInput.activeFocus && !titleInput.readOnly").toBool());
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);
        // The view buttons of the top bar, and «Editar» from the reading bar.
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("view-read")));
        QTRY_COMPARE(js("viewMode").toString(),QString("read"));
        QCOMPARE(settings(),QString("read"));
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("leaveReading")));
        QTRY_COMPARE(js("viewMode").toString(),QString("edit"));
        QVERIFY(js("blockRepeater.itemAt(1).editable").toBool());
        find("composeButton");

        // Diseño de página (Ctrl+Shift+D): Carta in Mexico with 2,54 cm margins, as many sheets as the text needs.
        QTest::keyClick(window,Qt::Key_D,Qt::ControlModifier|Qt::ShiftModifier);
        QTRY_COMPARE(js("viewMode").toString(),QString("page"));
        QCOMPARE(settings(),QString("page"));
        QCOMPARE(js("paper").toString(),QString("letter"));
        auto *sheets = find("paperSheets");
        QCOMPARE(sheets->width(),816.);
        QCOMPARE(js("pageColumn.width").toDouble(),816.-2*96);
        QVERIFY(!shown("pageCover"));
        QTRY_VERIFY(js("sheetCount").toInt() >= 3);
        // No block runs into the bottom margin of its sheet, and a heading stays on the sheet of what follows it.
        const QString layout = R"((function() {
            const stride = paperHeight+sheetGap, usable = paperHeight-2*marginY
            const sheetOf = r => Math.floor((r.y+1)/stride)
            for (let i = 0; i < blocks.count; ++i) {
                const r = blockRepeater.itemAt(i), local = r.y-sheetOf(r)*stride
                if (local < -1 || (r.height <= usable && local+r.height > usable+1)) return "block " + i + " at " + local
                if (r.kind === "heading" && i+1 < blocks.count && sheetOf(blockRepeater.itemAt(i+1)) !== sheetOf(r)) return "heading " + i
            }
            const last = blockRepeater.itemAt(blocks.count-1)
            return sheetOf(last)+1 === sheetCount ? "" : "sheets " + sheetCount + " for " + (sheetOf(last)+1)
        })())";
        QTRY_COMPARE(js(layout).toString(),QString());
        QVERIFY(js("pageBreaks.some(g => g > 0)").toBool());
        QTRY_COMPARE(sheets->property("count").toInt(),js("sheetCount").toInt());
        QCOMPARE(find("sheetCounter")->property("text").toString(),
                 QString("Página 1 de %1").arg(js("sheetCount").toInt()));
        capture("vista-pagina");
        // Between two sheets, and the same in the usual Claro theme.
        js("pageScroll.contentItem.contentY = deskMargin+paperHeight-pageScroll.availableHeight/4");
        QTRY_COMPARE(js("currentSheet").toInt(),2);
        capture("vista-pagina-salto");
        editor.setTheme("white");
        capture("vista-pagina-claro");
        editor.setTheme("dark");
        js("pageScroll.contentItem.contentY = pageScroll.contentHeight-pageScroll.availableHeight");
        QTRY_COMPARE(js("currentSheet").toInt(),js("sheetCount").toInt());
        capture("vista-pagina-final");
        // Writing goes on as in Edición.
        js("pageScroll.contentItem.contentY = 0; blockRepeater.itemAt(1).focusAt(0)");
        type("Hoy: ");
        QTRY_VERIFY(js("blocks.get(1).body").toString().startsWith("Hoy: "));
        QVERIFY(js("flush()").toBool());

        // The paper button: A4, then narrow margins; the text column follows and the sheets are laid out again.
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("paperButton")));
        QTRY_VERIFY(js("paperMenu.opened").toBool());
        capture("vista-pagina-papel");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("paper-a4")));
        QTRY_COMPARE(js("paper").toString(),QString("a4"));
        QTRY_COMPARE(sheets->width(),794.);
        QTRY_COMPARE(sheets->height(),js("sheetCount").toInt()*1123.+(js("sheetCount").toInt()-1)*24.);
        js("setMargins('narrow')");
        QTRY_COMPARE(js("pageColumn.width").toDouble(),794.-2*48);
        QTRY_COMPARE(js(layout).toString(),QString());
        QCOMPARE(editor.preference("paper").toString(),QString("a4"));
        QCOMPARE(editor.preference("margins").toString(),QString("narrow"));
        // A PDF comes out on that paper: A4 is 595 × 842 points.
        const QString pdf = temp.filePath("informe.pdf");
        QVERIFY(js(QString("!!call('export',{id: currentId, url: '%1', paper: paper, margins: margins})")
                   .arg(QUrl::fromLocalFile(pdf).toString())).toBool());
        QFile file(pdf);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray data = file.readAll();
        const qsizetype box = data.indexOf("/MediaBox");
        QVERIFY(box > 0);
        QVERIFY2(data.mid(box,40).contains("595"),data.mid(box,40).constData());

        // Back in Edición (Ctrl+Shift+E) the page is as before: cover, a single column, no sheets.
        QTest::keyClick(window,Qt::Key_E,Qt::ControlModifier|Qt::ShiftModifier);
        QTRY_COMPARE(js("viewMode").toString(),QString("edit"));
        QTRY_COMPARE(js("pageBreaks.length").toInt(),0);
        QVERIFY(!sheets->isVisible());
        QVERIFY(js("pageColumn.width").toDouble() <= 780);
        QVERIFY(shown("pageCover"));
        QVERIFY(window->close());
    }
    void lunqioMigrationFlow() {
        // Flowen used to be Lunqio. Data folders in Qt's test mode only: never the real ones.
        QStandardPaths::setTestModeEnabled(true);
        auto normal = qScopeGuard([] { QStandardPaths::setTestModeEnabled(false); });
        const QDir data(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation));
        QVERIFY2(data.absolutePath().contains("qttest",Qt::CaseInsensitive),qPrintable(data.absolutePath()));
        QVERIFY(notes::environment("DB").isEmpty());
        auto clean = [data] {
            if (!data.absolutePath().contains("qttest",Qt::CaseInsensitive)) return;
            QDir(data.filePath("Lunqio")).removeRecursively();
            QDir(data.filePath("Flowen")).removeRecursively();
        };
        clean();
        auto cleanAfter = qScopeGuard(clean);
        const QString legacy = notes::Store::legacyPath(), current = notes::Store::defaultPath();
        QVERIFY(legacy.endsWith("Lunqio/notas.sqlite3"));
        QVERIFY(current.endsWith("Flowen/notas.sqlite3"));
        QVERIFY(!notes::Store::adoptLunqio(current));             // No Lunqio library: nothing to bring.
        QString id;
        {
            notes::Store old(legacy);
            id = old.call("create_page",{{"title","Diario de Lunqio"},{"blocks",QJsonArray{
                Obj{{"type","paragraph"},{"text","Antes del cambio de nombre"}}}}},"manual")["id"].toString();
        }
        {
            QFile usage(data.filePath("Lunqio/usage.jsonl"));
            QVERIFY(usage.open(QIODevice::WriteOnly));
            usage.write("{\"tokens\":1}\n");
        }
        // Another library (a test, --db elsewhere) never copies Lunqio's.
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        QVERIFY(!notes::Store::adoptLunqio(temp.filePath("otra.sqlite3")));
        QVERIFY(!QFileInfo::exists(current));
        // The usual library copies it once, with the usage log; Lunqio's copy stays, with a note.
        QVERIFY(notes::Store::adoptLunqio(current));
        QVERIFY(!notes::Store::adoptLunqio(current));
        QVERIFY(QFileInfo::exists(legacy));
        QVERIFY(QFileInfo::exists(data.filePath("Flowen/usage.jsonl")));
        QVERIFY(QFileInfo::exists(data.filePath("Lunqio/LEEME - ahora en Flowen.txt")));
        {
            notes::Store store(current);
            QCOMPARE(store.page(id)["title"].toString(),QString("Diario de Lunqio"));
        }
        // A server registered with Lunqio's library opens Flowen's; any other path stays as it is.
        QCOMPARE(QFileInfo(notes::Store::resolve(legacy)),QFileInfo(current));
        QCOMPARE(notes::Store::resolve(temp.filePath("otra.sqlite3")),temp.filePath("otra.sqlite3"));

        // A Claude Desktop entry that Lunqio left on moves to Flowen's library by itself, named "flowen";
        // the other servers stay. One Lunqio left off waits for the person (outdated).
        auto readJson = [](const QString &path) {
            QFile file(path);
            return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : Obj();
        };
        auto writeJson = [](const QString &path, const Obj &value) {
            QFile file(path);
            QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
            file.write(QJsonDocument(value).toJson());
        };
        const QString config = temp.filePath("claude_desktop_config.json");
        writeJson(config,Obj{{"mcpServers",Obj{
            {"lunqio",Obj{{"command","C:/Lunqio/notas-mcp.exe"},{"args",QJsonArray{"--db",QDir::toNativeSeparators(legacy)}}}},
            {"otro",Obj{{"command","node"},{"args",QJsonArray{"servidor.js"}}}}}}});
        ClaudeDesktopConnector desktop(current,config);
        desktop.inspect();
        QTRY_COMPARE(desktop.state(),QString("on"));
        QCOMPARE(desktop.serverName(),QString("flowen"));
        auto servers = readJson(config)["mcpServers"].toObject();
        QVERIFY(!servers.contains("lunqio"));
        QVERIFY(servers.contains("otro"));
        QCOMPARE(servers["flowen"].toObject()["args"].toArray(),
                 QJsonArray({"--db",QDir::toNativeSeparators(QFileInfo(current).absoluteFilePath())}));
        writeJson(config,Obj{{"mcpServers",Obj{
            {"lunqio",Obj{{"command","C:/Lunqio/notas-mcp.exe"},{"args",QJsonArray{"--db",QDir::toNativeSeparators(legacy)}},{"disabled",true}}}}}});
        ClaudeDesktopConnector paused(current,config);
        paused.inspect();
        QTRY_COMPARE(paused.state(),QString("outdated"));
        QTest::qWait(200);
        QCOMPARE(paused.state(),QString("outdated"));
        QVERIFY(readJson(config)["mcpServers"].toObject().contains("lunqio"));
    }
    void helpAboutFlow() {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());
        notes::Store store(temp.filePath("ayuda.sqlite3"));
        const QString page = store.call("create_page",{{"title","Bienvenida"},{"icon",QString::fromUtf8("👋")},
            {"blocks",QJsonArray{Obj{{"type","paragraph"},{"text",QString::fromUtf8("Pulsa F1 para ver los atajos.")}}}}},"manual")["id"].toString();
        Editor editor(store,QCoreApplication::applicationFilePath());
        editor.setTheme("dark");
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl::fromLocalFile(QStringLiteral(UI_SOURCE_DIR "/Main.qml")));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        window->resize(1400,900);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        auto js = [&](const QString &code) {
            QQmlExpression e(qmlContext(window),window,code);
            auto value = e.evaluate();
            if (e.hasError()) QTest::qFail(qPrintable(e.error().toString()),__FILE__,__LINE__);
            return value;
        };
        auto capture = [&](const QString &name) {
            const auto dir = qEnvironmentVariable("FLOWEN_PREVIEW_DIR");
            if (dir.isEmpty()) return;
            QTest::qWait(300);
            QVERIFY(window->grabWindow().save(QDir(dir).filePath(name+".png")));
        };
        auto find = [&](const QString &name) {
            QQuickItem *item = nullptr;
            [&] { QTRY_VERIFY((item = visibleItem(window->contentItem(),name)) && item->isVisible() && item->width() > 0); }();
            return item;
        };
        auto centre = [](QQuickItem *it) { return it->mapToScene(it->boundingRect().center()).toPoint(); };
        js(QString("selectPage('%1')").arg(page));
        QTRY_COMPARE(js("currentId").toString(),page);

        // F1 opens the guide: every shortcut in a table by topic, the new views included.
        QTest::keyClick(window,Qt::Key_F1);
        QTRY_VERIFY(js("helpDialog.opened").toBool());
        QCOMPARE(js("helpDialog.sections.length").toInt(),5);
        QCOMPARE(js("helpDialog.sections.reduce((n, s) => n + s.rows.length, 0)").toInt(),28);
        QVERIFY(js("helpDialog.sections.some(s => s.rows.some(r => r[0] === 'Diseño de página' && r[1][0] === 'Ctrl+Shift+D'))").toBool());
        capture("guia-atajos");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("helpClose")));
        QTRY_VERIFY(!js("helpDialog.visible").toBool());

        // Acerca de: the version of this build and Attribute Overload, whose lockup follows the theme.
        js("openAbout()");
        QTRY_VERIFY(js("aboutDialog.opened").toBool());
        QCOMPARE(find("aboutVersion")->property("text").toString(),"Versión " + editor.version());
        QVERIFY(!editor.version().isEmpty());
        auto *lockup = find("studioImage");
        QVERIFY(lockup->property("source").toUrl().toString().endsWith("ao-lockup-white.png"));
        QTRY_COMPARE(lockup->property("status").toInt(),1);
        QCOMPARE(js("aboutDialog.site").toString(),QString("https://www.attributeoverload.com"));
        QCOMPARE(js("aboutDialog.repository").toString(),QString("https://github.com/robertocharretonkaplun/Flowen"));
        find("aboutSite"); find("aboutCode"); find("aboutDocs");
        capture("acerca-de");
        editor.setTheme("light");
        QTRY_VERIFY(lockup->property("source").toUrl().toString().endsWith("ao-lockup-ink.png"));
        QTRY_COMPARE(lockup->property("status").toInt(),1);
        capture("acerca-de-claro");
        editor.setTheme("dark");
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,centre(find("aboutClose")));
        QTRY_VERIFY(!js("aboutDialog.visible").toBool());
        QVERIFY(window->close());
    }
};
int main(int argc,char **argv) {
    if (argc > 1 && QByteArray(argv[1]) == "exec") {
        QCoreApplication cli(argc,argv);
        auto args = cli.arguments();
        QFile input;
        if (!input.open(stdin,QIODevice::ReadOnly)) return 1;
        auto prompt = input.readAll();
        auto data = QJsonDocument::fromJson(prompt.mid(prompt.indexOf('\n')+1)).object();
        if (data["selection"] != "revisar  el  resumen" || prompt.contains("Compartir el resumen")) return 2;
        QFile output(args.value(args.indexOf("-o")+1));
        if (!output.open(QIODevice::WriteOnly)) return 3;
        output.write(R"({"replacement":"revisar el resumen"})");
        // Codex `exec --json` reports token usage as a JSONL event on stdout.
        std::fputs(R"({"type":"turn.completed","usage":{"input_tokens":900,"cached_input_tokens":100,"output_tokens":50}})" "\n",stdout);
        return 0;
    }
    // Stands in for Claude Code: `auth status` and `-p --output-format json --json-schema ...`.
    if (argc > 1 && QByteArray(argv[1]) == "auth") { std::fputs("{\"loggedIn\":true,\"authMethod\":\"claude.ai\"}\n",stdout); return 0; }
    if (argc > 1 && QByteArray(argv[1]) == "-p") {
        QFile input;
        if (!input.open(stdin,QIODevice::ReadOnly)) return 1;
        const QByteArray prompt = input.readAll();
        QByteArray schema;
        for (int i = 1; i+1 < argc; ++i) if (QByteArray(argv[i]) == "--json-schema") schema = argv[i+1];
        if (prompt.contains("FALLA_LIMITE")) {
            std::fputs("{\"type\":\"result\",\"is_error\":true,\"result\":\"Claude AI usage limit reached\"}\n",stdout);
            return 1;
        }
        Obj answer;
        if (schema.contains("\"answer\"")) {
            // "Preguntar a Flowen": answer from the note that has the task, and name a note it was not given too.
            const auto data = QJsonDocument::fromJson(prompt.mid(prompt.indexOf('\n')+1)).object();
            QJsonArray used{QString("00000000-0000-0000-0000-000000000000")};
            QString text = "No encontré nada sobre eso en tus notas.";
            for (const auto &n : data["notes"].toArray()) {
                if (!n.toObject()["text"].toString().contains("Comprar boletos")) continue;
                used.append(n.toObject()["id"]);
                text = "Te falta:\n- Comprar boletos para el viaje";
            }
            answer = Obj{{"answer",text},{"sources",used}};
        } else if (schema.contains("\"blocks\"")) {
            const auto data = QJsonDocument::fromJson(prompt.mid(prompt.indexOf('\n')+1)).object();
            if (data["page_title"] != "Prototipos" || !data["text_before"].toString().contains("Notas de la clase")) return 3;
            answer = Obj{{"blocks",QJsonArray{
                Obj{{"type","heading"},{"text","## Prototipado en videojuegos"}},
                Obj{{"type","list"},{"text","- Probar ideas rápido"}},
                Obj{{"type","list"},{"text","Validar mecánicas antes de producir arte"}},
                Obj{{"type","task"},{"text","[ ] Hacer un prototipo en papel"}}}}};
        } else answer = Obj{{"replacement","revisar el resumen"}};
        const Obj reply{{"type","result"},{"subtype","success"},{"is_error",false},{"result",""},{"structured_output",answer},
            {"usage",Obj{{"input_tokens",1200},{"cache_creation_input_tokens",300},{"cache_read_input_tokens",5000},{"output_tokens",420}}},
            {"total_cost_usd",0.0123},{"modelUsage",Obj{{"claude-sonnet-prueba",Obj{{"contextWindow",200000}}}}}};
        // stream-json: the plan limits arrive as their own event before the result.
        std::fputs(R"({"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{)"
                   R"("five_hour":{"utilization":0.08,"resetsAt":1795128828},"seven_day":{"utilization":0.37,"resetsAt":1795631389}}}})" "\n",stdout);
        std::fputs((QJsonDocument(reply).toJson(QJsonDocument::Compact)+"\n").constData(),stdout);
        return 0;
    }
    QGuiApplication app(argc,argv);
    // Stands in for `codex app-server`: answers initialize and account/rateLimits/read.
    if (argc > 1 && QByteArray(argv[1]) == "app-server") {
        char line[8192];
        while (std::fgets(line,sizeof line,stdin)) {
            const auto message = QJsonDocument::fromJson(QByteArray(line)).object();
            const int id = message["id"].toInt(-1);
            if (id == 1) std::fputs("{\"id\":1,\"result\":{}}\n",stdout);
            else if (id == 2) {
                std::fputs(R"({"id":2,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1795128828},)"
                           R"("secondary":{"usedPercent":26,"windowDurationMins":10080,"resetsAt":1795631389},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}}}})" "\n",stdout);
                std::fflush(stdout);
                return 0;
            }
            std::fflush(stdout);
        }
        return 0;
    }
    if (argc > 2 && QByteArray(argv[1]) == "mcp") {
        // Stands in for `codex mcp list --json` when the tests pass this binary as Codex.
        if (QByteArray(argv[2]) == "list") std::fputs("[]\n",stdout);
        return 0;
    }
    EditorTest test;
    return QTest::qExec(&test,argc,argv);
}
#include "editor_test.moc"
