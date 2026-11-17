#include "source/FakeCar.h"

#include <QRandomGenerator>
#include <QtGlobal>

FakeCar::FakeCar(QObject *parent)
    : ICarSource(parent)
{
    m_tick.setInterval(10);                       // 100 Hz
    connect(&m_tick, &QTimer::timeout, this, &FakeCar::onTick);

    m_report.setInterval(100);                    // 10 Hz
    connect(&m_report, &QTimer::timeout, this, &FakeCar::onReport);
}

void FakeCar::start()
{
    if (m_running) return;
    m_running = true;
    m_estop   = 0;
    m_tick.start();
    m_report.start();
    emit connectedChanged(true);
}

void FakeCar::stop()
{
    if (!m_running) return;
    m_running = false;
    m_tick.stop();
    m_report.stop();
    emit connectedChanged(false);
}

void FakeCar::setServoAngle(quint16 angleX10)
{
    if (m_estop) return;                          // 急停后不接受角度指令
    m_targetX10 = qBound<quint16>(0, angleX10, 1800);
}

void FakeCar::sendEstop()
{
    m_estop     = 1;
    m_targetX10 = m_actualX10;                    // 停在当前角度
    emit eventReceived(2);                        // 2 = 急停触发
}

void FakeCar::onTick()
{
    // 舵机按 300 度/秒 逼近目标（SG90 量级：60 度约 0.2 秒）
    const int step = 30;                          // 0.1 度 / 10ms
    if (m_actualX10 < m_targetX10)
        m_actualX10 = qMin<quint16>(m_targetX10, static_cast<quint16>(m_actualX10 + step));
    else if (m_actualX10 > m_targetX10)
        m_actualX10 = qMax<quint16>(m_targetX10, static_cast<quint16>(m_actualX10 - step));

    m_distMm = measureDistance(m_actualX10);
}

quint16 FakeCar::measureDistance(quint16 angleX10) const
{
    // 虚拟房间：40..70 度方向有一堵约 300mm 的墙，其余方向 1200mm
    // 叠加 +/-15mm 抖动，模拟超声波噪声
    int base = 1200;
    if (angleX10 >= 400 && angleX10 <= 700)
        base = 300;

    const int noise = static_cast<int>(QRandomGenerator::global()->bounded(31)) - 15;
    int d = base + noise;
    if (d < 20) d = 20;
    return static_cast<quint16>(d);
}

void FakeCar::onReport()
{
    CarStatus s;
    s.servoX10 = m_actualX10;
    s.distMm   = m_distMm;
    s.errCode  = m_estop;
    emit statusReceived(s);
}