#pragma once
#include "store.h"

namespace pagefile {
QJsonObject insertPhoto(notes::Store &store,const QString &page,int revision,const QString &path);
QString storePhoto(notes::Store &store,const QString &path);
void save(notes::Store &store,const QJsonObject &page,const QString &path);
}
