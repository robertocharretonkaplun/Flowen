#pragma once
#include "store.h"
#include <QMimeData>

/// Files in and out of the library: photos (from disk or the clipboard) and pages saved as Markdown,
/// HTML, PDF or plain text.
namespace pagefile {
/// Stores a photo file and adds it as a block at the end of a page.
QJsonObject insertPhoto(notes::Store &store,const QString &page,int revision,const QString &path);
/// Stores a photo file in the library and returns its asset id.
QString storePhoto(notes::Store &store,const QString &path);
/// The clipboard as photos: image files copied in Explorer, or an image with no text of its own.
bool clipboardHasPhoto(const QMimeData *data);
QJsonArray storeClipboardPhotos(notes::Store &store,const QMimeData *data);
/// A photo of the library as a file (PNG or JPEG, as its name asks; converted if needed) or on the clipboard.
QString savePhoto(notes::Store &store,const QString &asset,QString path);
void copyPhoto(notes::Store &store,const QString &asset);
/// Saves a page in the format its extension asks for (.md, .html, .pdf, .txt). A PDF uses the page's
/// `paper` and `margins` when given (Diseño de página).
void save(notes::Store &store,const QJsonObject &page,const QString &path);
}
