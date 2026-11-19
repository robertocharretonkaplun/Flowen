#include "inlineeditor.h"
#include "inlines.h"
#include <QColor>
#include <QFont>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QRegularExpression>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QDateTime>
#include <QHash>
#include <QUuid>
#include <algorithm>

static_assert(int(InlineEditor::Bold) == notes::Bold && int(InlineEditor::Superscript) == notes::Superscript);
namespace {
constexpr int AllStyles = 127;
const int StyleProperty = QTextFormat::UserProperty + 1;
const int CommentProperty = QTextFormat::UserProperty + 2;
const int ThreadProperty = QTextFormat::UserProperty + 3;
QJsonObject threadOf(const QString &json) { return QJsonDocument::fromJson(json.toUtf8()).object(); }
QString compact(const QJsonObject &o) { return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact)); }

// The library stores only the style flags, link and comment. These are the
// colours the dark editor uses to draw them; exports use their own palette.
QTextCharFormat visual(const InlineEditor::Piece &p) {
    QTextCharFormat f;
    if (p.style) f.setProperty(StyleProperty,p.style);
    if (p.style & notes::Bold) f.setFontWeight(QFont::Bold);
    if (p.style & notes::Italic) f.setFontItalic(true);
    if (p.style & notes::Strike) f.setFontStrikeOut(true);
    if (p.style & notes::Superscript) f.setVerticalAlignment(QTextCharFormat::AlignSuperScript);
    const bool code = p.style & notes::Code;
    if (code) {
        f.setFontFamilies(QStringList{"Cascadia Mono","Consolas"});
        f.setFontFixedPitch(true);
        f.setForeground(QColor(0xe3,0xa0,0x96));
        f.setBackground(QColor(0x36,0x35,0x39));
    }
    if (!p.comment.isEmpty()) {
        f.setProperty(CommentProperty,p.comment);
        if (!p.thread.isEmpty()) f.setProperty(ThreadProperty,p.thread);
        // Resolved comments stay in the page but stop being highlighted.
        if (!code && !threadOf(p.thread)["resolved"].toBool()) f.setBackground(QColor(0x45,0x3b,0x22));
    }
    if (p.style & notes::Highlight) f.setBackground(QColor(0x5e,0x4c,0x22));
    bool underline = p.style & notes::Underline;
    if (!p.link.isEmpty()) {
        f.setAnchor(true);
        f.setAnchorHref(p.link);
        if (notes::pageLink(p.link)) {
            // A page mention reads as a chip rather than a web link.
            if (!code) { f.setForeground(QColor(0xdc,0xe6,0xf3)); f.setBackground(QColor(0x2c,0x31,0x3a)); }
        } else {
            underline = true;
            if (!code) f.setForeground(QColor(0xa4,0xbf,0xe5));
        }
    }
    if (underline) f.setFontUnderline(true);
    return f;
}
}

void InlineEditor::registerType() {
    qmlRegisterType<InlineEditor>("Lunqio",1,0,"InlineEditor");
}
QTextDocument *InlineEditor::doc() const {
    return source ? source->textDocument() : nullptr;
}
void InlineEditor::setDocument(QQuickTextDocument *document) {
    if (source == document) return;
    disconnect(watch);
    source = document;
    if (auto *d = doc())
        watch = connect(d,&QTextDocument::contentsChange,this,[this](int,int,int) {
            if (loading) return;
            refresh();
            emit contentChanged();
        });
    emit documentChanged();
    refresh();
}
void InlineEditor::setSelectionStart(int value) {
    if (from == value) return;
    from = value;
    emit selectionChanged();
    refresh();
}
void InlineEditor::setSelectionEnd(int value) {
    if (to == value) return;
    to = value;
    emit selectionChanged();
    refresh();
}
QList<InlineEditor::Piece> InlineEditor::pieces(int start, int end) const {
    QList<Piece> out;
    auto *d = doc();
    if (!d || start >= end) return out;
    for (auto block = d->findBlock(start); block.isValid() && block.position() < end; block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            if (!fragment.isValid()) continue;
            const int a = qMax(start,fragment.position()), b = qMin(end,fragment.position()+fragment.length());
            if (a >= b) continue;
            const auto f = fragment.charFormat();
            out.append({a,b,f.intProperty(StyleProperty) & AllStyles,f.isAnchor() ? f.anchorHref() : QString(),
                        f.stringProperty(CommentProperty),f.stringProperty(ThreadProperty)});
        }
    }
    return out;
}
void InlineEditor::refresh() {
    int s = 0;
    QString l, c, t;
    const auto list = pieces(from,to);
    if (!list.isEmpty()) {
        s = AllStyles; l = list.first().link; c = list.first().comment; t = threadOf(list.first().thread)["id"].toString();
        for (const auto &p : list) {
            s &= p.style;
            if (p.link != l) l.clear();
            if (p.comment != c) c.clear();
            if (threadOf(p.thread)["id"].toString() != t) t.clear();
        }
    }
    if (s == styles && l == link && c == comment && t == threadId) return;
    styles = s; link = l; comment = c; threadId = t;
    emit stateChanged();
}
void InlineEditor::load(const QString &text, const QString &spans) {
    auto *d = doc();
    if (!d) return;
    loading = true;
    d->setUndoRedoEnabled(false);
    d->setPlainText(text);
    const int length = int(text.size());
    QTextCursor cursor(d);
    for (const auto &value : QJsonDocument::fromJson(spans.toUtf8()).array()) {
        const auto s = value.toObject();
        Piece p{s["start"].toInt(),qMin(s["end"].toInt(),length),s["style"].toInt() & AllStyles,
                s["link"].toString(),s["comment"].toString(),{}};
        if (p.start < 0 || p.start >= p.end) continue;
        // Comments written before threads existed get an id so they can be answered and resolved.
        if (!p.comment.isEmpty()) {
            auto thread = s["thread"].toObject();
            if (thread["id"].toString().isEmpty()) thread["id"] = QUuid::createUuid().toString(QUuid::WithoutBraces);
            p.thread = compact(thread);
        }
        cursor.setPosition(p.start);
        cursor.setPosition(p.end,QTextCursor::KeepAnchor);
        cursor.setCharFormat(visual(p));
    }
    d->setUndoRedoEnabled(true);
    loading = false;
    refresh();
}
QString InlineEditor::text() const {
    auto *d = doc();
    return d ? d->toPlainText() : QString();
}
QString InlineEditor::spans() const {
    auto *d = doc();
    return d ? serialize(0,d->characterCount()) : QStringLiteral("[]");
}
// The spans of [start, end), counted from `start`.
QString InlineEditor::serialize(int start, int end) const {
    QJsonArray out;
    if (doc()) {
        for (auto p : pieces(start,end)) {
            if (!p.style && p.link.isEmpty() && p.comment.isEmpty()) continue;
            p.start -= start;
            p.end -= start;
            if (!out.isEmpty()) {
                auto previous = out.last().toObject();
                if (previous["end"].toInt() == p.start && previous["style"].toInt() == p.style &&
                    previous["link"].toString() == p.link && previous["comment"].toString() == p.comment &&
                    previous["thread"].toObject() == (p.comment.isEmpty() ? QJsonObject() : threadOf(p.thread))) {
                    previous["end"] = p.end;
                    out[out.size()-1] = previous;
                    continue;
                }
            }
            QJsonObject span{{"start",p.start},{"end",p.end},{"style",p.style}};
            if (!p.link.isEmpty()) span["link"] = p.link;
            if (!p.comment.isEmpty()) {
                span["comment"] = p.comment;
                if (!p.thread.isEmpty()) span["thread"] = threadOf(p.thread);
            }
            out.append(span);
        }
    }
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}
// Enter in the middle of a block: the text after the cursor (with its styles) moves to a new block.
QVariantMap InlineEditor::takeTail(int position) {
    auto *d = doc();
    if (!d) return {};
    const int length = d->characterCount()-1;
    position = qBound(0,position,length);
    const QVariantMap tail{{"text",d->toPlainText().mid(position)},{"spans",serialize(position,length)}};
    if (position < length) {
        QTextCursor cursor(d);
        cursor.setPosition(position);
        cursor.setPosition(length,QTextCursor::KeepAnchor);
        cursor.removeSelectedText();
    }
    return tail;
}
// Backspace at the start of a block: its text joins the end of this one. Returns where they meet.
int InlineEditor::append(const QString &text, const QString &tail) {
    auto *d = doc();
    if (!d) return 0;
    const int at = d->characterCount()-1;
    QTextCursor cursor(d);
    cursor.beginEditBlock();
    cursor.setPosition(at);
    cursor.insertText(text,QTextCharFormat());
    for (const auto &value : QJsonDocument::fromJson(tail.toUtf8()).array()) {
        const auto s = value.toObject();
        Piece p{at+s["start"].toInt(),at+qMin(s["end"].toInt(),int(text.size())),s["style"].toInt() & AllStyles,
                s["link"].toString(),s["comment"].toString(),s.contains("thread") ? compact(s["thread"].toObject()) : QString()};
        if (p.start >= p.end) continue;
        cursor.setPosition(p.start);
        cursor.setPosition(p.end,QTextCursor::KeepAnchor);
        cursor.setCharFormat(visual(p));
    }
    cursor.endEditBlock();
    return at;
}
// Markdown while typing: **negrita**, *cursiva*, _cursiva_, ~~tachado~~ and `código` become styles
// once the closing mark is typed. Returns the new cursor position, or -1 when nothing matched.
int InlineEditor::markdownAt(int position) {
    auto *d = doc();
    if (!d || position <= 0) return -1;
    const QTextBlock block = d->findBlock(position-1);
    const QString line = block.text().left(position-block.position());
    struct Rule { const char *pattern; int marker; int style; };
    static const Rule rules[] = {
        {R"((?<![*\\])\*\*([^*\s](?:[^*]*[^*\s])?)\*\*$)",2,notes::Bold},
        {R"((?<![~\\])~~([^~\s](?:[^~]*[^~\s])?)~~$)",2,notes::Strike},
        {R"((?<![`\\])`([^`]+)`$)",1,notes::Code},
        {R"((?<![*\w\\])\*([^*\s](?:[^*]*[^*\s])?)\*$)",1,notes::Italic},
        {R"((?<![_\w\\])_([^_\s](?:[^_]*[^_\s])?)_$)",1,notes::Italic},
    };
    for (const auto &rule : rules) {
        const QRegularExpression pattern(QString::fromLatin1(rule.pattern));
        const auto match = pattern.match(line);
        if (!match.hasMatch()) continue;
        const int start = block.position()+int(match.capturedStart(0));
        const int inner = int(match.capturedLength(1));
        QTextCursor cursor(d);
        cursor.beginEditBlock();
        cursor.setPosition(position-rule.marker);
        cursor.setPosition(position,QTextCursor::KeepAnchor);
        cursor.removeSelectedText();
        cursor.setPosition(start);
        cursor.setPosition(start+rule.marker,QTextCursor::KeepAnchor);
        cursor.removeSelectedText();
        for (auto p : pieces(start,start+inner)) {
            p.style |= rule.style;
            cursor.setPosition(p.start);
            cursor.setPosition(p.end,QTextCursor::KeepAnchor);
            cursor.setCharFormat(visual(p));
        }
        cursor.endEditBlock();
        refresh();
        return start+inner;
    }
    return -1;
}
// "@" or "[[" picked a page: the typed query becomes a mention of it, followed by a plain space.
int InlineEditor::insertMention(int start, int end, const QString &title, const QString &pageId) {
    auto *d = doc();
    const QString link = "lunqio://page/"+pageId, name = title.simplified().left(240);
    if (!d || name.isEmpty() || !notes::pageLink(link) || start < 0 || end < start || end >= d->characterCount()) return -1;
    QTextCursor cursor(d);
    cursor.beginEditBlock();
    cursor.setPosition(start);
    cursor.setPosition(end,QTextCursor::KeepAnchor);
    cursor.removeSelectedText();
    cursor.insertText(name,visual({start,start+int(name.size()),0,link,{},{}}));
    cursor.insertText(" ",QTextCharFormat());
    cursor.endEditBlock();
    refresh();
    return start+int(name.size())+1;
}
void InlineEditor::rewrite(const std::function<void(Piece &)> &edit) { rewriteRange(from,to,edit); }
void InlineEditor::rewriteRange(int start, int end, const std::function<void(Piece &)> &edit) {
    auto *d = doc();
    const auto list = pieces(start,end);
    if (!d || list.isEmpty()) return;
    QTextCursor cursor(d);
    cursor.beginEditBlock();
    for (auto p : list) {
        edit(p);
        cursor.setPosition(p.start);
        cursor.setPosition(p.end,QTextCursor::KeepAnchor);
        cursor.setCharFormat(visual(p));
    }
    cursor.endEditBlock();
    refresh();
}
void InlineEditor::toggle(int style) {
    style &= AllStyles;
    const auto list = pieces(from,to);
    if (!style || list.isEmpty()) return;
    const bool all = std::all_of(list.begin(),list.end(),[&](const Piece &p) { return (p.style & style) == style; });
    rewrite([&](Piece &p) { p.style = all ? p.style & ~style : p.style | style; });
}
void InlineEditor::clearStyles() {
    rewrite([](Piece &p) { p.style = 0; });
}
QString InlineEditor::normalizedLink(const QString &url) {
    QString value = url.trimmed();
    if (value.isEmpty()) return {};
    if (!value.contains("://")) value.prepend("https://");
    return notes::webLink(value) && value.toUcs4().size() <= 2048 ? value : QString();
}
bool InlineEditor::setLink(const QString &url) {
    const QString value = normalizedLink(url);
    if (value.isEmpty() && !url.trimmed().isEmpty()) return false;
    rewrite([&](Piece &p) { p.link = value; });
    return true;
}
namespace {
QString clip(QString value) {
    value = value.trimmed();
    if (value.size() > 1024) {
        value.truncate(1024);
        if (value.back().isHighSurrogate()) value.chop(1);
    }
    return value;
}
QString clipName(QString name) { return name.simplified().left(80); }
QString now() { return QDateTime::currentDateTimeUtc().toString(Qt::ISODate); }
}
// Empty text removes the comment from the selection.
void InlineEditor::setComment(const QString &text) {
    const QString value = clip(text);
    rewrite([&](Piece &p) {
        if (value.isEmpty()) { p.comment.clear(); p.thread.clear(); return; }
        p.comment = value;
        if (p.thread.isEmpty()) p.thread = compact({{"id",QUuid::createUuid().toString(QUuid::WithoutBraces)}});
    });
}
QString InlineEditor::commentAt(int position) const {
    const auto list = pieces(position,position+1);
    return list.isEmpty() ? QString() : list.first().comment;
}
QString InlineEditor::threadAt(int position) const {
    const auto list = pieces(position,position+1);
    return list.isEmpty() || list.first().comment.isEmpty() ? QString() : threadOf(list.first().thread)["id"].toString();
}
QString InlineEditor::addComment(int start, int end, const QString &text, const QString &author) {
    const QString value = clip(text);
    auto *d = doc();
    if (!d || value.isEmpty() || start < 0 || end <= start || end >= d->characterCount()) return {};
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString thread = compact({{"id",id},{"author",clipName(author)},{"at",now()},{"resolved",false},{"replies",QJsonArray()}});
    rewriteRange(start,end,[&](Piece &p) { p.comment = value; p.thread = thread; });
    return id;
}
// Applies one change to every piece of a thread, wherever it is in this block.
bool InlineEditor::updateThread(const QString &id, const std::function<void(Piece &)> &edit) {
    auto *d = doc();
    if (!d || id.isEmpty()) return false;
    const auto all = pieces(0,d->characterCount());
    const bool found = std::any_of(all.begin(),all.end(),[&](const Piece &p) { return !p.comment.isEmpty() && threadOf(p.thread)["id"] == id; });
    if (!found) return false;
    QTextCursor cursor(d);
    cursor.beginEditBlock();
    for (auto p : all) {
        if (p.comment.isEmpty() || threadOf(p.thread)["id"] != id) continue;
        edit(p);
        cursor.setPosition(p.start);
        cursor.setPosition(p.end,QTextCursor::KeepAnchor);
        cursor.setCharFormat(visual(p));
    }
    cursor.endEditBlock();
    refresh();
    return true;
}
bool InlineEditor::reply(const QString &id, const QString &text, const QString &author) {
    const QString value = clip(text);
    if (value.isEmpty()) return false;
    const QJsonObject message{{"author",clipName(author)},{"at",now()},{"text",value}};
    bool full = false;
    const bool done = updateThread(id,[&](Piece &p) {
        auto thread = threadOf(p.thread);
        auto replies = thread["replies"].toArray();
        if (replies.size() >= 50) { full = true; return; }
        replies.append(message);
        thread["replies"] = replies;
        p.thread = compact(thread);
    });
    return done && !full;
}
bool InlineEditor::setResolved(const QString &id, bool resolved) {
    return updateThread(id,[&](Piece &p) {
        auto thread = threadOf(p.thread);
        thread["resolved"] = resolved;
        p.thread = compact(thread);
    });
}
bool InlineEditor::editComment(const QString &id, const QString &text) {
    const QString value = clip(text);
    if (value.isEmpty()) return false;
    return updateThread(id,[&](Piece &p) { p.comment = value; });
}
bool InlineEditor::removeComment(const QString &id) {
    return updateThread(id,[](Piece &p) { p.comment.clear(); p.thread.clear(); });
}
bool InlineEditor::removeReply(const QString &id, int index) {
    return updateThread(id,[&](Piece &p) {
        auto thread = threadOf(p.thread);
        auto replies = thread["replies"].toArray();
        if (index < 0 || index >= replies.size()) return;
        replies.removeAt(index);
        thread["replies"] = replies;
        p.thread = compact(thread);
    });
}
// One entry per thread, with the commented words, for the comment cards.
QVariantList InlineEditor::comments() const {
    QVariantList out;
    QHash<QString,qsizetype> seen;
    auto *d = doc();
    if (!d) return out;
    const QString text = d->toPlainText();
    for (const auto &p : pieces(0,d->characterCount())) {
        if (p.comment.isEmpty()) continue;
        const auto thread = threadOf(p.thread);
        const QString id = thread["id"].toString();
        if (id.isEmpty()) continue;
        if (seen.contains(id)) {
            auto entry = out[seen[id]].toMap();
            entry["end"] = p.end;
            entry["quote"] = text.mid(entry["start"].toInt(),p.end-entry["start"].toInt());
            out[seen[id]] = entry;
            continue;
        }
        seen.insert(id,out.size());
        out << QVariantMap{{"id",id},{"text",p.comment},{"author",thread["author"].toString()},{"at",thread["at"].toString()},
                           {"resolved",thread["resolved"].toBool()},{"replies",thread["replies"].toArray().toVariantList()},
                           {"start",p.start},{"end",p.end},{"quote",text.mid(p.start,p.end-p.start)}};
    }
    return out;
}
