#include "ui/MainWindow.h"

#include <QApplication>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    MainWindow w;
    w.resize(640, 460);
    w.show();

    return app.exec();
}