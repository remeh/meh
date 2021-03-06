#include <QApplication>
#include <QByteArray>
#include <QFile>
#include <QLocalSocket>
#include <QObject>
#include <QStringList>
#include <QStyleFactory>
#include <QThread>

#include <stdio.h>

#include "buffer.h"
#include "editor.h"
#include "git.h"
#include "window.h"

#include "qdebug.h"

int main(int argv, char **args)
{
    QApplication app(argv, args);
    app.setCursorFlashTime(0);
    app.setWheelScrollLines(5);
    app.setStyle(QStyleFactory::create("Fusion"));
    QCoreApplication::setOrganizationName("mehteor");

    QCoreApplication::setOrganizationDomain("remy.io");
    QCoreApplication::setApplicationName("meh");
    QStringList arguments = QCoreApplication::arguments();

    if (!arguments.empty() && QFile::exists("/tmp/meh.sock") &&
         arguments.size() >= 2 && arguments.at(1) != "-n" &&
         !Git::isGitTempFile(arguments.at(1))) {

        QLocalSocket socket;
        socket.connectToServer("/tmp/meh.sock");

        if (socket.state() != QLocalSocket::ConnectedState) {
            qDebug() << "An error happened while connecting to /tmp/meh.sock" <<
                socket.errorString();
            qDebug() << "Will create a new instance instead.";
        } else {
            arguments.removeFirst();
            if (arguments.empty()) {
                arguments.append("/tmp/meh-notes");
            }
            for (int i = 0; i < arguments.size(); i++) {
                QFileInfo fi(arguments.at(i));
                arguments[i] = fi.absoluteFilePath();
            }
            QString data = "open " + arguments.join("###");
            socket.write(data.toLatin1());
            socket.flush();
            socket.close();
            return 0;
        }
    }

    if (arguments.size() >= 2 && arguments.at(1) == "-n") {
        arguments.remove(1);
    }

	qDebug() << "Creating a new instance.";

    Window window(&app);
    window.setWindowTitle(QObject::tr("meh - no file"));
    window.resize(800, 700);
    window.show();

    // special case of reading from stdin
    if (arguments.size() > 1 && arguments.at(1) == "-") {

        QByteArray content;

        QFile in;
        if (!in.open(stdin, QIODevice::ReadOnly)) {
            qWarning() << "can't read stdin";
            qWarning() << in.errorString();
        }
        content += in.readAll();
        in.close();

        window.newEditor("stdin", content);
    } else if (arguments.size() > 0) {
        for (int i = arguments.size() - 1; i > 0; i--) {
            if (arguments.at(i).startsWith("+")) {
                continue;
            }

            QFileInfo fi(arguments.at(i));
            if (fi.isDir()) {
                continue;
            }

            window.newEditor(arguments.at(i), arguments.at(i));
        }

        // special cases about the last one
        if (arguments.last().startsWith("+")) {
            bool ok = false;
            int lineNumber = arguments.last().toInt(&ok);
            if (ok) {
                window.getEditor()->goToLine(lineNumber);
            }
        } else if (arguments.size() > 1) {
            // the last one is not a +###
            // checks whether it is a directory, if it is, we want to
            // set it as the base work dir.
            QFileInfo fi(arguments.last());
            if (fi.isDir()) {
                window.setBaseDir(fi.absoluteFilePath());
                window.openListFiles();
            }
        }
    } else {
        window.newEditor("notes", QString("/tmp/meh-notes"));
    }

    return app.exec();
}

