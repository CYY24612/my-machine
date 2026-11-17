// CarController.h —— 应用层：状态机 + 把界面操作翻译成数据源调用
#pragma once

#include "source/ICarSource.h"

#include <QObject>

class CarController : public QObject
{
    Q_OBJECT
public:
    enum class State { Disconnected, Ready, Fault };
    Q_ENUM(State)

    explicit CarController(QObject *parent = nullptr);

    void attach(ICarSource *src);

public slots:
    void connectSource();
    void disconnectSource();
    void setServoDegrees(int degrees);   // 0..180 度
    void setServoX10(int angleX10);      // 0..1800
    void estop();

signals:
    void stateChanged(CarController::State s);
    void statusUpdate(const CarStatus &s);
    void logMessage(const QString &msg);

private slots:
    void onStatus(const CarStatus &s);
    void onEvent(quint8 code);
    void onConn(bool c);

private:
    void setState(State s);

    ICarSource *m_src   = nullptr;
    State       m_state = State::Disconnected;
};