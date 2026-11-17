#include "ui/MainWindow.h"
#include "source/FakeCar.h"

#include <QDateTime>
#include <QHBoxLayout>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSlider>
#include <QVBoxLayout>
#include <QWidget>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    // 顺序要紧：buildUi() 里要把急停按钮连到 m_ctrl，所以控制器必须先建
    m_ctrl = new CarController(this);
    m_ctrl->attach(new FakeCar(this));          // ← 换成 SerialCar 就是真车

    buildUi();

    connect(m_ctrl, &CarController::statusUpdate, this, &MainWindow::onStatus);
    connect(m_ctrl, &CarController::stateChanged, this, &MainWindow::onStateChanged);
    connect(m_ctrl, &CarController::logMessage,   this, &MainWindow::appendLog);

    setLamp(QStringLiteral("#8a8a8a"));
    appendLog(QStringLiteral("就绪：当前为【假车】数据源"));
}

MainWindow::~MainWindow() = default;

void MainWindow::buildUi()
{
    auto *central = new QWidget(this);
    auto *v = new QVBoxLayout(central);

    // ---- 状态灯 + 两个数字 ----
    auto *top = new QHBoxLayout;

    m_lamp = new QLabel(this);
    m_lamp->setFixedSize(14, 14);
    top->addWidget(new QLabel(QStringLiteral("连接："), this));
    top->addWidget(m_lamp);
    top->addSpacing(20);

    m_angle = new QLabel(QStringLiteral("0.0 °"), this);
    m_angle->setStyleSheet(QStringLiteral("font-size:20px;font-weight:bold;"));
    top->addWidget(new QLabel(QStringLiteral("舵机："), this));
    top->addWidget(m_angle);
    top->addSpacing(20);

    m_dist = new QLabel(QStringLiteral("--- mm"), this);
    m_dist->setStyleSheet(QStringLiteral("font-size:20px;font-weight:bold;"));
    top->addWidget(new QLabel(QStringLiteral("距离："), this));
    top->addWidget(m_dist);
    top->addStretch();
    v->addLayout(top);

    // ---- 角度滑块 ----
    m_slider = new QSlider(Qt::Horizontal, this);
    m_slider->setRange(0, 180);
    m_slider->setValue(90);
    connect(m_slider, &QSlider::valueChanged, this, &MainWindow::onSliderMoved);
    v->addWidget(new QLabel(QStringLiteral("目标角度（0..180°，松手不回中）"), this));
    v->addWidget(m_slider);

    // ---- 按钮 ----
    auto *btns = new QHBoxLayout;
    m_connectBtn = new QPushButton(QStringLiteral("连接"), this);
    m_estopBtn   = new QPushButton(QStringLiteral("急停"), this);
    m_estopBtn->setStyleSheet(QStringLiteral("color:#b00;font-weight:bold;"));
    connect(m_connectBtn, &QPushButton::clicked, this, &MainWindow::onConnectClicked);
    connect(m_estopBtn,   &QPushButton::clicked, m_ctrl, &CarController::estop);
    btns->addWidget(m_connectBtn);
    btns->addWidget(m_estopBtn);
    btns->addStretch();
    v->addLayout(btns);

    // ---- 日志 ----
    m_log = new QPlainTextEdit(this);
    m_log->setReadOnly(true);
    m_log->setMaximumBlockCount(500);
    v->addWidget(m_log, 1);

    setCentralWidget(central);
    setWindowTitle(QStringLiteral("我的车 · 遥控器 v0.1"));
}

void MainWindow::onConnectClicked()
{
    if (!m_connected)
        m_ctrl->connectSource();
    else
        m_ctrl->disconnectSource();
}

void MainWindow::onSliderMoved(int v)
{
    m_ctrl->setServoDegrees(v);
}

void MainWindow::onStatus(const CarStatus &s)
{
    m_angle->setText(QStringLiteral("%1 °").arg(s.servoX10 / 10.0, 0, 'f', 1));
    m_dist->setText(QStringLiteral("%1 mm").arg(s.distMm));
}

void MainWindow::onStateChanged(CarController::State s)
{
    using S = CarController::State;
    m_connected = (s == S::Ready);
    m_connectBtn->setText(m_connected ? QStringLiteral("断开") : QStringLiteral("连接"));
    m_estopBtn->setEnabled(m_connected);

    switch (s) {
    case S::Ready:        setLamp(QStringLiteral("#2ecc71")); break;
    case S::Fault:        setLamp(QStringLiteral("#e74c3c")); break;
    case S::Disconnected: setLamp(QStringLiteral("#8a8a8a")); break;
    }
}

void MainWindow::setLamp(const QString &color)
{
    m_lamp->setStyleSheet(QStringLiteral("background:%1;border-radius:7px;").arg(color));
}

void MainWindow::appendLog(const QString &msg)
{
    m_log->appendPlainText(QStringLiteral("[%1] %2")
                               .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")),
                                    msg));
}