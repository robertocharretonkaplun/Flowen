#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <functional>

class QTextDocument;

// Keeps the inline styles of one block TextArea in its QTextDocument and
// converts them to and from the `spans` stored in the library.
class InlineEditor : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    Q_PROPERTY(int selectionStart READ selectionStart WRITE setSelectionStart NOTIFY selectionChanged)
    Q_PROPERTY(int selectionEnd READ selectionEnd WRITE setSelectionEnd NOTIFY selectionChanged)
    Q_PROPERTY(int activeStyles READ activeStyles NOTIFY stateChanged)
    Q_PROPERTY(QString activeLink READ activeLink NOTIFY stateChanged)
    Q_PROPERTY(QString activeComment READ activeComment NOTIFY stateChanged)
    Q_PROPERTY(QString activeThread READ activeThread NOTIFY stateChanged)
public:
    enum Style { Bold=1, Italic=2, Underline=4, Strike=8, Code=16, Highlight=32, Superscript=64 };
    Q_ENUM(Style)
    explicit InlineEditor(QObject *parent = nullptr) : QObject(parent) {}
    static void registerType();
    QQuickTextDocument *document() const { return source; }
    void setDocument(QQuickTextDocument *document);
    int selectionStart() const { return from; }
    int selectionEnd() const { return to; }
    void setSelectionStart(int value);
    void setSelectionEnd(int value);
    int activeStyles() const { return styles; }
    QString activeLink() const { return link; }
    QString activeComment() const { return comment; }
    QString activeThread() const { return threadId; }
    Q_INVOKABLE void load(const QString &text, const QString &spans);
    Q_INVOKABLE QString text() const;
    Q_INVOKABLE QString spans() const;
    Q_INVOKABLE void toggle(int style);
    Q_INVOKABLE void clearStyles();
    Q_INVOKABLE bool setLink(const QString &url);
    Q_INVOKABLE void setComment(const QString &text);
    Q_INVOKABLE QString commentAt(int position) const;
    // Comment threads: each one keeps its author, time, state and replies next to the text.
    Q_INVOKABLE QVariantMap takeTail(int position);
    Q_INVOKABLE int append(const QString &text, const QString &styles);
    Q_INVOKABLE int markdownAt(int position);
    Q_INVOKABLE int insertMention(int start, int end, const QString &title, const QString &pageId);
    Q_INVOKABLE QString addComment(int start, int end, const QString &text, const QString &author);
    Q_INVOKABLE QVariantList comments() const;
    Q_INVOKABLE QString threadAt(int position) const;
    Q_INVOKABLE bool reply(const QString &id, const QString &text, const QString &author);
    Q_INVOKABLE bool setResolved(const QString &id, bool resolved);
    Q_INVOKABLE bool editComment(const QString &id, const QString &text);
    Q_INVOKABLE bool removeComment(const QString &id);
    Q_INVOKABLE bool removeReply(const QString &id, int index);
    Q_INVOKABLE static QString normalizedLink(const QString &url);
signals:
    void documentChanged();
    void selectionChanged();
    void stateChanged();
    void contentChanged();
public:
    struct Piece { int start = 0, end = 0, style = 0; QString link, comment, thread; };
private:
    QTextDocument *doc() const;
    QList<Piece> pieces(int start, int end) const;
    QString serialize(int start, int end) const;
    void rewrite(const std::function<void(Piece &)> &edit);
    void rewriteRange(int start, int end, const std::function<void(Piece &)> &edit);
    bool updateThread(const QString &id, const std::function<void(Piece &)> &edit);
    void refresh();
    QPointer<QQuickTextDocument> source;
    QMetaObject::Connection watch;
    int from = 0, to = 0, styles = 0;
    QString link, comment, threadId;
    bool loading = false;
};
