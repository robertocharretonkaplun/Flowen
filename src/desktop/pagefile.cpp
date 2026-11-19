#include "pagefile.h"
#include "inlines.h"
#include <QBuffer>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QPageLayout>
#include <QPdfWriter>
#include <QSaveFile>
#include <QTextDocument>
#include <QUrl>

namespace pagefile {
using Obj = QJsonObject;
static void fail(const QString &message) { throw notes::Error("file_error",message); }
static QByteArray readPhoto(const QString &path,QString &mime);
Obj insertPhoto(notes::Store &store,const QString &page,int revision,const QString &path) {
    QString mime;
    const QByteArray bytes = readPhoto(path,mime);
    return store.insertPhoto(page,revision,QFileInfo(path).completeBaseName(),mime,bytes);
}
QString storePhoto(notes::Store &store,const QString &path) {
    QString mime;
    const QByteArray bytes = readPhoto(path,mime);
    return store.addPhoto(mime,bytes);
}
static QByteArray readPhoto(const QString &path,QString &mime) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) fail("No se pudo abrir la foto.");
    if (file.size() > 32*1024*1024) fail("Elige una foto de hasta 32 MiB.");
    QImageReader reader(&file);
    reader.setDecideFormatFromContent(true);
    reader.setAutoTransform(true);
    const auto format = reader.format().toLower();
    if (format != "png" && format != "jpeg" && format != "jpg") fail("Elige una foto PNG o JPEG.");
    const auto size = reader.size();
    if (!size.isValid() || qint64(size.width())*size.height() > 40000000) fail("Elige una imagen válida de hasta 40 megapíxeles.");
    QImage image = reader.read();
    if (image.isNull()) fail("No se pudo leer la imagen completa.");
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    bool png = format == "png";
    if (!image.save(&buffer,png ? "PNG" : "JPEG",png ? -1 : 94)) fail("No se pudo preparar la foto.");
    mime = png ? "image/png" : "image/jpeg";
    return bytes;
}
static void write(QIODevice &file,const QByteArray &data) {
    if (file.write(data) != data.size()) fail("No se pudo escribir el archivo completo.");
}
static QString markdownPhoto(const QFileInfo &note,const QString &asset,const QString &mime,const QByteArray &bytes) {
    QString folder = note.completeBaseName()+".media";
    if (!note.dir().mkpath(folder)) fail("No se pudo crear la carpeta de fotos de Markdown.");
    QString relative = folder+'/'+asset+(mime == "image/png" ? ".png" : ".jpg");
    const auto path = note.dir().filePath(relative);
    if (QFileInfo::exists(path)) {
        QFile existing(path);
        if (!existing.open(QIODevice::ReadOnly) || existing.size() != bytes.size() || existing.readAll() != bytes)
            fail("Ya existe una foto distinta en la carpeta de exportación. Elige otro nombre para la nota.");
    } else {
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly)) fail("No se pudo guardar una foto de Markdown.");
        write(file,bytes);
        if (!file.commit()) fail("No se pudo guardar una foto de Markdown.");
    }
    return QString::fromLatin1(QUrl::toPercentEncoding(relative,"/"));
}
static QString htmlText(QString text) {
    return text.toHtmlEscaped().replace("\n","<br>");
}
// The number shown before each "numbered" block: consecutive items at the same indent count up.
static QList<int> numbering(const QJsonArray &blocks) {
    QList<int> out;
    QList<int> counters(8,0);
    for (const auto &v : blocks) {
        const auto b = v.toObject();
        const int indent = qBound(0,b["indent"].toInt(),6);
        for (int deeper = indent+1; deeper < counters.size(); ++deeper) counters[deeper] = 0;
        if (b["type"] == "numbered") out << ++counters[indent];
        else { counters[indent] = 0; out << 0; }
    }
    return out;
}
static QString htmlBlock(const Obj &b, int number = 0) {
    QString content = notes::inlineHtml(b), kind = b["type"].toString(), html;
    if (kind == "heading") html = QString("<h%1>%2</h%1>").arg(qBound(1,b["level"].toInt(1),3)+1).arg(content);
    else if (kind == "list") html = "<ul><li>"+content+"</li></ul>";
    else if (kind == "numbered") html = QString("<p>%1. %2</p>").arg(qMax(1,number)).arg(content);
    else if (kind == "quote") html = "<blockquote>"+content+"</blockquote>";
    else if (kind == "callout") html = "<p style=\"background-color:#f1f1ef;padding:8px\">"+b["icon"].toString("💡").toHtmlEscaped()+" "+content+"</p>";
    else if (kind == "code") html = "<pre>"+b["text"].toString().toHtmlEscaped()+"</pre>";
    else if (kind == "toggle") html = "<p>▸ "+content+"</p>";
    else if (kind == "divider") html = "<hr>";
    else {
        if (kind == "task") content.prepend(b["checked"].toBool() ? "☑ " : "☐ ");
        html = "<p>"+content+"</p>";
    }
    const int indent = b["indent"].toInt();
    return indent > 0 ? QString("<div style=\"margin-left:%1px\">%2</div>").arg(indent*24).arg(html) : html;
}
// Markdown and plain text for a block without inline styles.
static QString plainBlock(const Obj &b, int number, bool md) {
    QString text = b["text"].toString(), kind = b["type"].toString();
    const QString lead = QString(qMax(0,b["indent"].toInt())*4,' ');
    if (kind == "heading") return md ? QString(qBound(1,b["level"].toInt(1),3)+1,'#')+" "+text : text;
    if (kind == "list") return lead+"- "+text;
    if (kind == "numbered") return lead+QString::number(qMax(1,number))+". "+text;
    if (kind == "task") return lead+(b["checked"].toBool() ? "- [x] " : "- [ ] ")+text;
    if (kind == "quote") return lead+"> "+text;
    if (kind == "callout") return lead+"> "+b["icon"].toString("💡")+" "+text;
    if (kind == "code") return md ? "```\n"+text+"\n```" : text;
    if (kind == "toggle") return lead+"▸ "+text;
    if (kind == "divider") return md ? "---" : "――――――――";
    return lead+text;
}
static QString titled(const Obj &page) {
    const QString icon = page["icon"].toString();
    return icon.isEmpty() ? page["title"].toString() : icon+" "+page["title"].toString();
}
static void printable(notes::Store &store,const Obj &page,QSaveFile &file) {
    QPdfWriter writer(&file);
    writer.setPageSize(QPageSize(QPageSize::A4));
    writer.setPageMargins(QMarginsF(16,16,16,16),QPageLayout::Millimeter);
    writer.setResolution(96);
    writer.setTitle(page["title"].toString());
    const QSize area = writer.pageLayout().paintRectPixels(96).size();
    QTextDocument doc;
    doc.setPageSize(area);
    doc.setDocumentMargin(0);
    QString html = "<h1>"+htmlText(titled(page))+"</h1>";
    const auto blocks = page["blocks"].toArray();
    const auto numbers = numbering(blocks);
    for (qsizetype i = 0; i < blocks.size(); ++i) {
        auto b = blocks[i].toObject();
        if (b["type"] != "image") { html += htmlBlock(b,numbers[i]); continue; }
        const auto asset = b["asset"].toString();
        QString mime;
        auto image = QImage::fromData(store.photo(asset,mime));
        if (image.isNull()) fail("No se pudo preparar una foto para el PDF.");
        const QSize display = image.size().scaled(qMax(1,(area.width()-2)*b["width_percent"].toInt()/100),
                                                  area.height()-50,Qt::KeepAspectRatio);
        const QUrl resource("lunqio:/"+asset+"/"+QString::number(display.width()));
        doc.addResource(QTextDocument::ImageResource,resource,image.scaled(display*2,Qt::KeepAspectRatio,Qt::SmoothTransformation));
        html += QString("<p><img src=\"%1\" width=\"%2\" height=\"%3\"></p>").arg(resource.toString()).arg(display.width()).arg(display.height());
        if (!b["text"].toString().isEmpty()) html += "<p><i>"+htmlText(b["text"].toString())+"</i></p>";
    }
    doc.setHtml(html);
    doc.print(&writer);
    if (file.pos() <= 0 || file.error() != QFileDevice::NoError) fail("No se pudo generar el PDF.");
}
void save(notes::Store &store,const Obj &page,const QString &path) {
    QFileInfo target(path);
    auto ext = target.suffix().toLower();
    bool html = ext == "html" || ext == "htm", md = ext == "md", pdf = ext == "pdf";
    if (!html && !md && !pdf && ext != "txt") fail("Elige la extensión .md, .txt, .html o .pdf.");
    if (target == QFileInfo(store.path())) fail("Elige un archivo distinto al de la biblioteca.");
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) fail("No se pudo abrir el archivo de destino.");
    QString title = titled(page);
    if (pdf) printable(store,page,file);
    else {
        if (html) write(file,("<!doctype html><html lang=\"es\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>"+
            title.toHtmlEscaped()+"</title><style>body{max-width:48rem;margin:3rem auto;padding:0 1rem;font:1.1rem/1.55 system-ui;color:#202020}figure{margin:1rem 0}img{max-width:100%;height:auto}figcaption{color:#555}blockquote{margin:0;padding-left:1rem;border-left:3px solid #202020}pre{background:#f4f4f2;padding:12px;border-radius:6px;overflow:auto}</style><body><h1>"+htmlText(title)+"</h1>\n").toUtf8());
        else write(file,((md ? "# "+title : title)+"\n\n").toUtf8());
        const auto blocks = page["blocks"].toArray();
        const auto numbers = numbering(blocks);
        for (qsizetype i = 0; i < blocks.size(); ++i) {
            auto b = blocks[i].toObject();
            QString kind = b["type"].toString(), text = b["text"].toString();
            if (kind == "image") {
                if (!html && !md) text = "[Foto] "+text;
                else {
                    QString mime,asset = b["asset"].toString();
                    auto bytes = store.photo(asset,mime);
                    QString src = html ? "data:"+mime+";base64,"+QString::fromLatin1(bytes.toBase64()) : markdownPhoto(target,asset,mime,bytes);
                    QString tag = QString("<img src=\"%1\" alt=\"%2\" width=\"%3%\">").arg(src.toHtmlEscaped(),text.toHtmlEscaped(),QString::number(b["width_percent"].toInt()));
                    text = html ? "<figure>"+tag+"<figcaption>"+htmlText(text)+"</figcaption></figure>" : tag;
                }
            } else if (html || (md && !b["spans"].toArray().isEmpty() && kind != "code")) text = htmlBlock(b,numbers[i]);
            else text = plainBlock(b,numbers[i],md);
            write(file,(text+"\n\n").toUtf8());
        }
        if (html) write(file,"</body></html>\n");
    }
    if (!file.commit()) fail("No se pudo terminar de guardar el archivo.");
}
}
