// MainWindow.h —— 界面层：只负责显示和收集用户操作，不处理任何协议细节
#pragma once

#include "app/CarController.h"

#include <QMainWindow>

class QLabel;
class QSlider;
class QPushButton;
class QPlainTextEdit;

class MainWindow : public QMainWindow
{
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

private slots:
    void onStatus(const CarStatus &s);
    void onStateChanged(CarController::State s);
    void onSliderMoved(int v);
    void onConnectClicked();

private:
    void buildUi();
    void appendLog(const QString &msg);
    void setLamp(const QString &color);

    bool           m_connected = false;
    CarController *m_ctrl      = nullptr;

    QLabel         *m_angle = nullptr;
    QLabel         *m_dist  = nullptr;
    QLabel         *m_lamp  = nullptr;
    QSlider        *m_slider = nullptr;
    QPushButton    *m_connectBtn = nullptr;
    QPushButton    *m_estopBtn   = nullptr;
    QPlainTextEdit *m_log = nullptr;
};