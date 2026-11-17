// ICarSource.h —— 数据源抽象：界面只认这个接口，不知道背后是真车还是假车
#pragma once

#include <QObject>
#include <QtGlobal>

struct CarStatus {
    quint16 servoX10 = 0;   // 舵机角度，单位 0.1 度（0..1800）
    quint16 distMm   = 0;   // 超声波距离，单位 mm
    quint8  errCode  = 0;   // 错误码，0 = 正常
};

class ICarSource : public QObject
{
    Q_OBJECT
public:
    explicit ICarSource(QObject *parent = nullptr) : QObject(parent) {}
    ~ICarSource() override = default;

    virtual void start() = 0;
    virtual void stop()  = 0;
    virtual void setServoAngle(quint16 angleX10) = 0;
    virtual void sendEstop() = 0;
    virtual bool isConnected() const = 0;

signals:
    void statusReceived(const CarStatus &s);
    void eventReceived(quint8 code);
    void connectedChanged(bool connected);
};