#include "mode.h"
#include "tasks.h"
#include "window.h"

TasksPlugin::TasksPlugin(Window* window) :
    window(window) {
    Q_ASSERT(window != nullptr);
}

QList<HighlightingRule> TasksPlugin::getSyntaxRules() {
    QList<HighlightingRule> rv;

    HighlightingRule rule;
    QTextCharFormat tasksDone, tasksWontDo;

    tasksDone.setForeground(QColor::fromRgb(153,215,0));
    rule.pattern = QRegularExpression(QStringLiteral("\\[v\\] .*"));
    rule.format = tasksDone;
    rv.append(rule);

    tasksWontDo.setForeground(Qt::red);
    rule.pattern = QRegularExpression(QStringLiteral("\\[x\\] .*"));
    rule.format = tasksWontDo;
    rv.append(rule);

    return rv;
}

void TasksPlugin::keyPressEvent(QKeyEvent* event, bool ctrl, bool shift) {
    Q_ASSERT(event != nullptr);

    Editor* editor = this->window->getEditor();
    Q_ASSERT(editor != nullptr);

    QString text;

    switch (event->key()) {
        case Qt::Key_N:
            if (shift) {
                editor->insertNewLine(true, true);
            } else {
                editor->insertNewLine(false, true);
            }

            // we never want a new task to not have an indent
            if (editor->textCursor().positionInBlock() == 0) {
                editor->textCursor().insertText("    [ ] ");
            } else {
                editor->textCursor().insertText("[ ] ");
            }

            editor->setMode(MODE_INSERT);
            editor->setSubMode(NO_SUBMODE);
            return;
        case Qt::Key_C:
            if (shift) {
                editor->insertNewLine(true, true);
            } else {
                editor->insertNewLine(false, true);
            }
            editor->textCursor().insertText("# ");
            editor->setMode(MODE_INSERT);
            editor->setSubMode(NO_SUBMODE);
            return;
        case Qt::Key_D:
            editor->textCursor().beginEditBlock();
            text = editor->textCursor().block().text();
            if (text.contains("[v] ")) {
                text.replace("[v] ", "[ ] "); // cancel
            } else {
                text.replace("[ ] ", "[v] "); // done
                text.replace("[x] ", "[v] "); // done
            }
            editor->deleteCurrentLine();
            editor->textCursor().insertText(text);
            editor->textCursor().endEditBlock();
            break;
        case Qt::Key_X:
            editor->textCursor().beginEditBlock();
            text = editor->textCursor().block().text();
            if (text.contains("[x] ")) {
                text.replace("[x] ", "[ ] "); // cancel
            } else {
                text.replace("[ ] ", "[x] "); // done
                text.replace("[v] ", "[x] "); // done
            }
            editor->deleteCurrentLine();
            editor->textCursor().insertText(text);
            editor->textCursor().endEditBlock();
            break;
    }

    editor->setMode(MODE_NORMAL);
    editor->setSubMode(NO_SUBMODE);
}
