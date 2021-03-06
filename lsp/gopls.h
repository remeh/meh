#include <QJsonObject>
#include <QList>
#include <QString>

#include "../buffer.h"

class CompleterEntry;
class LSP;
class LSPWriter;
class Window;

class LSPGopls : public LSP
{
public:
    LSPGopls(Window* window, const QString& baseDir);
    ~LSPGopls() override;
    void readStandardOutput() override;

    // protocol
    bool start() override;
    void openFile(Buffer* buffer) override;
    void refreshFile(Buffer* buffer) override;
    void initialize(Buffer* buffer) override;
    void definition(int reqId, const QString& filename, int line, int column) override;
    void declaration(int reqId, const QString& filename, int line, int column) override;
    void hover(int reqId, const QString& filename, int line, int column) override;
    void signatureHelp(int reqId, const QString& filename, int line, int column) override;
    void references(int reqId, const QString& filename, int line, int column) override;
    void completion(int reqId, const QString& filename, int line, int column) override;
    QList<CompleterEntry> getEntries(const QJsonDocument& json) override;

private:
    QString baseDir;
    LSPWriter writer;
};
