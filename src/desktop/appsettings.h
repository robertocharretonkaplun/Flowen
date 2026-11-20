#pragma once
#include <QSettings>

/// Flowen's preferences in the user's profile: theme, view and paper, chosen programs, connector state.
/// Everything that remembers something between sessions goes through here.
inline QSettings appSettings() {
    return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Flowen","Editor");
}
/// The first time Flowen starts after being Lunqio, it keeps Lunqio's preferences (Lunqio's own stay).
inline void adoptLunqioSettings() {
    QSettings now = appSettings();
    if (!now.allKeys().isEmpty()) return;
    QSettings old(QSettings::defaultFormat(),QSettings::UserScope,"Lunqio","Editor");
    for (const QString &key : old.allKeys()) now.setValue(key,old.value(key));
}
