#pragma once
#include "store.h"
#include <QMimeData>

namespace pagefile {
QJsonObject insertPhoto(notes::Store &store,const QString &page,int revision,const QString &path);
QString storePhoto(notes::Store &store,const QString &path);
// The clipboard as photos: image files copied in Explorer, or an image with no text of its own.
bool clipboardHasPhoto(const QMimeData *data);
QJsonArray storeClipboardPhotos(notes::Store &store,const QMimeData *data);
void save(notes::Store &store,const QJsonObject &page,const QString &path);
}
