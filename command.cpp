#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QMessageBox>
#include <QRandomGenerator>
#include <QSettings>

#include "qdebug.h"

#include "command.h"
#include "exec.h"
#include "lsp.h"
#include "git.h"
#include "window.h"

Command::Command(Window* window) :
    QLineEdit(window),
    window(window) {
    Q_ASSERT(window != NULL);
    this->setFont(Editor::getFont());
}

void Command::keyPressEvent(QKeyEvent* event) {
    Q_ASSERT(event != NULL);

    switch (event->key()) {
        case Qt::Key_Escape:
            this->clear();
            this->window->closeCommand();
            if (this->window->getEditor()) {
                this->window->getEditor()->highlightText("");
            }
            return;
        case Qt::Key_Up:
            {
                QSettings settings("mehteor", "meh");
                const QStringList list = settings.value("command/history").toStringList();
                if (list.size() == 0 || list.size() <= this->historyIdx) {
                    return;
                }
                const QString v = list.at(list.size() - 1 - this->historyIdx);
                this->setText(v);
                this->historyIdx++;
                return;
            }
        case Qt::Key_Return:
            this->execute(this->text());
            this->window->closeCommand();
            return;
    }

    QLineEdit::keyPressEvent(event);

    // highlight search
    if (this->text().size() > 0 && this->text()[0] == '/') {
        if (this->window->getEditor()) {
            this->window->getEditor()->setSearchText(QString("(?i)") + this->text().mid(1));
        }
    }
}

void Command::show() {
    this->historyIdx = 0;
    QLineEdit::show();
    QLineEdit::raise();

    QRect cursorRect = this->window->getEditor()->cursorRect();
    int winWidth = this->window->size().width();
    int winHeight = this->window->size().height();
    int popupWidth = winWidth  - winWidth/3;
    QWidget::show();
    QWidget::raise();
    this->resize(600, 32);
    this->move(cursorRect.x() + 50, cursorRect.y() + 30);

    // move it somewhere visible if not visible
    if (this->pos().y() < 0 || this->pos().y() > winHeight) {
        this->move(winWidth / 2 - (winWidth/3), 120);
    }
}

bool Command::warningModifiedBuffers() {
	QStringList modifiedBuffersIds = this->window->modifiedBuffersIds();
	if (modifiedBuffersIds.size() > 0) {
		QString msg = "Some opened buffers have not been saved:\n\n";
		for (int i = 0; i < modifiedBuffersIds.size(); i++) {
			msg += modifiedBuffersIds.at(i) + "\n";
		}
		QMessageBox::warning(this->window, "Unsaved buffers", msg);
		return true;
	}
	return false;
}

void Command::execute(QString text) {
    this->clear();

    QSettings settings("mehteor", "meh");
    QStringList commands = settings.value("command/history").toStringList();
    if (commands.size() == 0 || commands.last() != text) {
        commands.append(text);
    }
    while (commands.size() > 1000) {
        commands.removeFirst();
    }
    settings.setValue("command/history", commands);

    QStringList list = text.split(" ");
    QString& command = list[0];

    // some alias
    // ----------------------

    if (command == ":fd") {
        list[0] = ":!fd";
        command = QString(":!fd");
    }

    // misc commands
    // ----------------------

    if (command == ":pwd" || command == ":basedir") {
        this->window->getStatusBar()->setMessage("Base dir: " + this->window->getBaseDir());
        this->window->getStatusBar()->showMessage();
        return;
    }

    if (command == ":cd") {
        list.removeFirst();
        QString bd;
        if (list.size() == 0) {
            // go to current file directory
            if (this->window->getEditor() == nullptr) { return; }
            QFileInfo fi(this->window->getEditor()->getBuffer()->getFilename());
            bd = fi.canonicalPath();
        } else {
            QString path = list.join(" ").trimmed();
            bd = this->window->getBaseDir();
            if (path.startsWith("/")) {
                bd = path;
            } else {
                bd += path;
            }
        }
        QDir d(bd);
        if (!d.exists()) {
            this->window->getStatusBar()->setMessage("Can't set base dir to: " + d.canonicalPath() + "\nIt doesn't exist");
            return;
        }
        this->window->setBaseDir(d.canonicalPath());
        this->window->getStatusBar()->setMessage("Base dir set to: " + this->window->getBaseDir());
        return;
    }

    // quit
    // ----------------------

    if (command == ":q" || command == ":qa") {
		if (this->warningModifiedBuffers()) {
			return;
		}
        QCoreApplication::quit();
        return;
    }

    if (command == ":q!" || command == ":qa!") {
        QCoreApplication::quit();
        return;
    }

    if (command == ":x" || command == ":x!") {
        if (list.size() > 1) {
            // TODO(remy):  save to another file
        }
        this->window->save();
		if (this->warningModifiedBuffers()) {
			return;
		}
        QCoreApplication::quit();
        return;
    }

    if (command == ":xa" || command == ":xa!") {
        if (list.size() > 1) {
            // TODO(remy):  save to another file
        }
        this->window->saveAll();
        QCoreApplication::quit();
        return;
    }

    // git
    // --------------

    if (command == ":gblame") {
        if (this->window->getEditor() == nullptr) {
            return;
        }
        Buffer* buffer = this->window->getEditor()->getBuffer();
        if (buffer == nullptr) {
            return;
        }
        this->window->getEditor()->getGit()->blame();
        return;
    }

    if (command == ":gshow") {
        if (this->window->getEditor() == nullptr) {
            return;
        }

        // gshow is used to show the commit of a given checksum
        // if no parameter is given, use the word under the cursor for the checksum
        QString checksum;
        if (list.size() > 1) {
            checksum = list[1];
        } else if (this->window->getEditor()->getBuffer() != nullptr) {
            checksum = this->window->getEditor()->getWordUnderCursor();
        } else {
            this->window->getStatusBar()->setMessage("no checksum provided");
            return;
        }
        this->window->getEditor()->getGit()->show(this->window->getBaseDir(), checksum);
    }

    if (command == ":gdiff") {
        if (this->window->getEditor() == nullptr) {
            return;
        }

        bool stat = false;
        bool staged = false;
        if (list.size() > 1) {
            if (list[1] == "--staged") {
                staged = true;
            }
            if (list[1] == "-r" || list[1] == "--refresh") {
                stat = true;
            }
        }
        this->window->getEditor()->getGit()->diff(staged, stat);
        return;
    }

    // date insertion
    // --------------

    if (command == ":d") {
        QDateTime now = QDateTime::currentDateTime();
        QString v = now.toString("yyyy-MM-dd");
        QTextCursor cursor = this->window->getEditor()->textCursor();
        cursor.movePosition(QTextCursor::Right, QTextCursor::MoveAnchor);
        cursor.insertText(" " + v);
        this->window->getEditor()->setTextCursor(cursor);
        return;
    }

    if (command == ":dt") {
        QDateTime now = QDateTime::currentDateTime();
        QString v = now.toString("yyyy-MM-dd hh:mm:ss");
        QTextCursor cursor = this->window->getEditor()->textCursor();
        cursor.movePosition(QTextCursor::Right, QTextCursor::MoveAnchor);
        cursor.insertText(" " + v);
        return;
    }

    // exec a command
    // --------------

    if (command.startsWith(":!") || command.startsWith("!") || command == ":exec") {
        if (command.startsWith("!")) {
            list[0] = QString(command).remove(0, 1);
        } else if (command.startsWith(":!")) {
            list[0] = QString(command).remove(0, 2);
        } else {
            list.removeFirst();
        }
        this->window->getExec()->start(this->window->getBaseDir(), list);
        return;
    }

    // lsp
    // ----------------------

    Buffer* currentBuffer = this->window->getEditor()->getBuffer();
    LSP* lsp = this->window->getLSPManager()->getLSP(currentBuffer->getId());
    int reqId = QRandomGenerator::global()->generate();
    if (reqId < 0) { reqId *= -1; }

    if (command == ":def") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->definition(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_DEFINITION, currentBuffer);
    }

    if (command == ":dec") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->declaration(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_DECLARATION, currentBuffer);
    }

    if (command == ":sig") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->signatureHelp(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_SIGNATURE_HELP, currentBuffer);
    }

    if (command == ":i" || command == ":info") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->hover(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_HOVER, currentBuffer);
    }

    if (command == ":ref") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->references(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_REFERENCES, currentBuffer);
    }

    if (command == ":com") {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        lsp->completion(reqId, currentBuffer->getFilename(), this->window->getEditor()->currentLineNumber(), this->window->getEditor()->currentColumn());
        this->window->getLSPManager()->setExecutedAction(reqId, LSP_ACTION_COMPLETION, currentBuffer);
    }

    if (command.startsWith(":err")) {
        if (lsp == nullptr) { this->window->getStatusBar()->setMessage("No LSP server running."); return; }
        Editor* editor = this->window->getEditor();
        if (editor == nullptr) {
            qDebug() << "error: command: `:err` window->getEditor() == nullptr";
            return;
        }
        if (command == ":errlist" || command == ":errl") {
            this->window->showLSPDiagnostics(editor->getId());
        } else if (command == ":err") {
            this->window->showLSPDiagnosticsOfLine(editor->getId(), editor->currentLineNumber());
        }
        return;

    }

    if (command == ":rlsp" || command == ":reloadlsp") {
        this->window->getLSPManager()->reload(currentBuffer);
        this->window->getStatusBar()->setLspRunning(false);
    }

    // close the current bnuffer
    // ----------------------

    if (command == ":bd") {
        this->window->closeCurrentEditor();
        return;
    }

    // close every unmodified buffers
    // XXX(remy): reimplement me
//    if (command == ":bu") {
//        QMap<QString, Buffer*>& buffers = this->window->getEditor()->getBuffers();
//        QList<QString> keys = buffers.keys();
//        for (int i = 0; i < keys.size(); i++) {
//            Buffer* buffer = buffers[keys.at(i)];
//            if (!buffer->modified) {
//                this->window->getEditor()->deleteBuffer(buffer);
//                buffers.remove(keys.at(i));
//           }
//        }
//        return;
//    }

    if (command == ":bd!") {
        if (this->window->getEditor()->getBuffer() == nullptr) {
            return;
        }
        this->window->closeCurrentEditor();
        return;
    }

    // print the whole history commands
    // --------------------------------

    if (command == ":history") {
        QSettings settings("mehteor", "meh");
        auto list = settings.value("command/history").toStringList();
        this->window->getStatusBar()->setMessage(list.join("\n"));
    }

    // go to a specific line
    // ----------------------

    if (command.size() > 1 && command.at(0) == ':' && command.at(1).isDigit()) {
        QStringView lineStr = QStringView{command}.right(command.size() - 1);
        bool ok = true;
        int line = lineStr.toInt(&ok);
        if (ok) {
            this->window->getEditor()->goToLine(line);
        }
        return;
    }

    // run figlet and insert
    // ----------------------

    if (command.startsWith(":figlet")) {
        QProcess figlet;
        QString copy = text.replace(":figlet ", "");
        figlet.start("figlet", QStringList() << "-f" << "small" << copy);
        figlet.waitForFinished();
        QByteArray data = figlet.readAll();
        this->window->getEditor()->insertPlainText(data);
        return;
    }

    if (command.startsWith(":title")) {
        QString copy = text.replace(":title ", "");
        QString rv = "#";
        for (int i = 0; i < copy.size()+3; i++) {
            rv += "#";
        }
        rv += "\n";
        rv += "# " + copy + " #\n";
        rv += "#";
        for (int i = 0; i < copy.size()+3; i++) {
            rv += "#";
        }
        rv += "\n";
        this->window->getEditor()->insertPlainText(rv);
        return;
    }

    // search next occurrence of a string
    // ----------------------

    if (command.size() >= 1 && command.at(0) == '/') {
        QString terms = "";
        if (command.size() > 1) {
            QStringList search;
            QStringView first = QStringView{command}.right(command.size() - 1);
            search << first.toString();
            for (int i = 1; i < list.size(); i++) {
               search << list.at(i);
            }
            terms = search.join(" ");
        } else {
            terms = this->window->getEditor()->getWordUnderCursor();
        }
        this->window->getEditor()->setSearchText(terms);
        this->window->saveCheckpoint();
        this->window->getEditor()->goToOccurrence(terms, false);
        this->window->getEditor()->centerCursor();
        return;
    }

    // grep
    // ----------------------

    if (command.startsWith(":rg")) {
        QString search = "";

        if (list.size() > 1) {
            QStringList listCopy = list;
            listCopy.removeFirst();
            search = listCopy.join(" ");
        } else {
            search = this->window->getEditor()->getWordUnderCursor();
        }

        if (command.startsWith(":rgf")) {
            this->window->openGrep(search, this->window->getEditor()->getBuffer()->getFilename());
        } else {
            this->window->openGrep(search);
        }

        return;
    }

    // file
    // ----------------------

    // open

    if (command == ":e" && list.size() > 1) {
        for (int i = 1; i < list.size(); i++) {
            const QString& file = list[i];
            this->window->newEditor(file, file);
        }
        return;
    }

    if (command == ":notes") {
        this->window->setCurrentEditor("/tmp/meh-notes.md");
        return;
    }

    // reload

    // XXX(remy): reimplement me
//    if (command == ":reload") {
//        Buffer* buffer = this->window->getEditor()->getBuffer();
//        if (buffer == nullptr) {
//            return;
//        }
//        if (!this->window->areYouSure("Are you sure to reload this file? Last changes may be lost.")) {
//            return;
//        }
//
//        int position = this->window->getEditor()->textCursor().position();
//        this->window->getEditor()->setPlainText(buffer->reload());
//        QTextCursor cursor = this->window->getEditor()->textCursor();
//        cursor.setPosition(position);
//        this->window->getEditor()->setTextCursor(cursor);
//        this->window->getEditor()->centerCursor();
//        return;
//    }

    // save

    if (command == ":w") {
        if (list.size() > 1) {
            // TODO(remy): save to another file
        }
        this->window->save();
    }

    if (command == ":wa") {
        this->window->saveAll();
    }
}
