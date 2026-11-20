#pragma once
#include "contract.h"
#include <QSqlDatabase>
#include <QSqlQuery>

/// The library: pages, their blocks, revisions, photos and comments in one SQLite file, shared by the
/// window (Lunqio) and the MCP server (notas-mcp).
namespace notes {
/// One open library. Every change goes through the contract (contract.h) and keeps a revision, so the
/// window and MCP clients can edit the same pages and notice conflicts (`expected_revision`).
class Store {
public:
    /// Where the library lives unless LUNQIO_DB says otherwise (the user's application data folder).
    static QString defaultPath();
    /// The SQLite file this store has open.
    QString path() const { return db.databaseName(); }
    /// Opens (and if needed creates or upgrades) the library at `path`; `readOnly` only allows the read tools.
    Store(const QString &path, bool readOnly = false);
    ~Store();
    Store(const Store &) = delete;
    Store &operator=(const Store &) = delete;
    /// Runs one MCP tool (create_page, get_page, update_page, apply_block_changes, search_notes…) after
    /// checking its arguments. `actor` ("manual" or "mcp") is kept in the page's history.
    /// Throws notes::Error with a stable code (invalid_argument, not_found, revision_conflict…).
    QJsonObject call(const QString &name, const QJsonObject &args, const QString &actor);
    /// A page with its blocks, look and revision, as get_page returns it.
    QJsonObject page(const QString &id);
    /// Every page outside the trash, for the sidebar tree.
    QJsonArray navigation();
    /// The revisions of a page, newest first.
    QJsonArray history(const QString &id);
    /// Pages that mention this one, with a snippet of the mention.
    QJsonArray backlinks(const QString &id);
    /// Ids of the favourite pages, in the order chosen.
    QJsonArray favorites();
    /// The most recently opened pages, newest first.
    QJsonArray recent(int limit);
    /// Adds a page to Favoritos (at `index`, or at the end) or takes it out.
    void setFavorite(const QString &id, bool on, int index = -1);
    /// Records that a page was opened, for Recientes; it creates no revision.
    void visit(const QString &id);
    /// The passages most related to a question, for Preguntar a Lunqio (`current` first if it is relevant).
    QJsonArray notesFor(const QString &question, const QString &current, int limit = 6);
    /// The templates saved from pages.
    QJsonArray templates();
    /// Saves a page's title, look and blocks (without comments) as a template called `name`.
    void saveTemplate(const QString &pageId, const QString &name);
    /// Deletes a saved template.
    void removeTemplate(const QString &id);
    /// A number that changes with every change to the library, so the window notices MCP edits.
    qint64 generation();
    /// Saves the editor's draft of a page if it is still at revision `expected`.
    QJsonObject saveDraft(const QString &id, int expected, const QString &title, QJsonArray blocks);
    /// Brings back an earlier revision as a new one.
    QJsonObject restoreRevision(const QString &id, int expected, int target);
    /// Adds a photo block at the end of a page.
    QJsonObject insertPhoto(const QString &id, int expected, const QString &caption,
                            const QString &mime, const QByteArray &bytes);
    /// Stores a photo once (by its SHA-256) and returns its asset id.
    QString addPhoto(const QString &mime, const QByteArray &bytes);
    /// The bytes of a stored photo and its type.
    QByteArray photo(const QString &asset, QString &mime);
    /// A consistent copy of the whole library (photos included) at `destination`.
    void backup(const QString &destination);
private:
    QSqlDatabase db;
    bool readOnly;
    QSqlQuery sql(const QString &statement, const QVariantList &values = {});
    QJsonObject load(const QString &id);
    QJsonObject checked(const QString &id, int expected, bool deleted = false);
    QJsonObject record(QJsonObject page, const QString &actor, bool rewriteBlocks = false);
    QJsonObject mutate(const QString &name, const QJsonObject &args, const QString &actor);
    QJsonObject read(const QString &name, const QJsonObject &args);
    void checkParent(const QString &id, const QJsonValue &parent);
    void assignParent(QJsonObject &page, const QJsonValue &parent);
    void refold();
    void renameMentions(const QString &id, const QString &before, const QString &after, const QString &actor);
};
}
