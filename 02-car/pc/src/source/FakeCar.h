// FakeCar.h —— 假车：不接任何硬件，用定时器模拟舵机运动与超声波测距
// 目的：让界面在没硬件时就能做完（见 长期目标 · 我的机器 → 交汇点①）
#pragma once

#include "source/ICarSource.h"

#include <QTimer>

class FakeCar : public ICarSource
{
    Q_OBJECT
public:
    explicit FakeCar(QObject *parent = nullptr);

    void start() override;
    void stop()  override;
    void setServoAngle(quint16 angleX10) override;
    void sendEstop() override;
    bool isConnected() const override { return m_running; }

private slots:
    void onTick();        // 100 Hz：舵机运动 + 测距
    void onReport();      //  10 Hz：发 STATUS

private:
    quint16 measureDistance(quint16 angleX10) const;

    QTimer  m_tick;
    QTimer  m_report;
    bool    m_running   = false;
    quint16 m_targetX10 = 900;
    quint16 m_actualX10 = 900;
    quint16 m_distMm    = 0;
    quint8  m_estop     = 0;
};