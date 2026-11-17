#include "app/CarController.h"

CarController::CarController(QObject *parent)
    : QObject(parent)
{
}

void CarController::attach(ICarSource *src)
{
    if (m_src) {
        disconnect(m_src, nullptr, this, nullptr);
        m_src = nullptr;
    }
    m_src = src;
    if (!m_src) return;

    connect(m_src, &ICarSource::statusReceived,   this, &CarController::onStatus);
    connect(m_src, &ICarSource::eventReceived,    this, &CarController::onEvent);
    connect(m_src, &ICarSource::connectedChanged, this, &CarController::onConn);
}

void CarController::connectSource()
{
    if (!m_src) {
        emit logMessage(QStringLiteral("没有数据源"));
        return;
    }
    m_src->start();
}

void CarController::disconnectSource()
{
    if (m_src) m_src->stop();
}

void CarController::setServoDegrees(int degrees)
{
    setServoX10(degrees * 10);
}

void CarController::setServoX10(int angleX10)
{
    if (!m_src || m_state != State::Ready) return;
    m_src->setServoAngle(static_cast<quint16>(qBound(0, angleX10, 1800)));
}

void CarController::estop()
{
    if (!m_src) return;
    m_src->sendEstop();
    emit logMessage(QStringLiteral("急停已触发（需重连解除）"));
}

void CarController::onStatus(const CarStatus &s)
{
    emit statusUpdate(s);
}

void CarController::onEvent(quint8 code)
{
    QString name;
    switch (code) {
    case 1: name = QStringLiteral("失联停机"); break;
    case 2: name = QStringLiteral("急停触发"); break;
    case 3: name = QStringLiteral("堵转");     break;
    default: name = QStringLiteral("未知(%1)").arg(code); break;
    }
    emit logMessage(QStringLiteral("事件：%1").arg(name));
}

void CarController::onConn(bool c)
{
    setState(c ? State::Ready : State::Disconnected);
    emit logMessage(c ? QStringLiteral("已连接") : QStringLiteral("已断开"));
}

void CarController::setState(State s)
{
    if (m_state == s) return;
    m_state = s;
    emit stateChanged(s);
}