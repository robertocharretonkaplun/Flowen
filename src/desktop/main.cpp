#include "editor.h"
#include "inlineeditor.h"
#include "svgglyph.h"
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QIcon>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#ifdef Q_OS_WIN
#include <windows.h>
#endif

int main(int argc, char **argv) {
    QGuiApplication app(argc,argv);
    app.setApplicationName("Lunqio");
    app.setWindowIcon(QIcon(":/assets/lunqio-256.png"));
    // The interface is in Spanish: dates and times follow it ("mié", "4:40 p.m."), keeping a Spanish system region.
    const QLocale system = QLocale::system();
    QLocale::setDefault(system.language() == QLocale::Spanish ? system : QLocale(QLocale::Spanish,QLocale::Mexico));
    QCommandLineParser cli;
    cli.addHelpOption();
    cli.addOption({"db","Ruta absoluta de la biblioteca.","archivo",notes::Store::defaultPath()});
    cli.process(app);
    try {
        notes::Store store(cli.value("db"));
        Editor editor(store);
        QQuickStyle::setStyle("Basic");
        InlineEditor::registerType();
        SvgGlyph::registerType();
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("backend",&editor);
        engine.load(QUrl("qrc:/qml/Main.qml"));
        if (engine.rootObjects().isEmpty()) return 1;
        return app.exec();
    } catch (const std::exception &e) {
        qCritical("%s",e.what());
#ifdef Q_OS_WIN
        MessageBoxW(nullptr,reinterpret_cast<LPCWSTR>(QString::fromUtf8(e.what()).utf16()),L"Lunqio",MB_ICONERROR);
#endif
        return 1;
    }
}
