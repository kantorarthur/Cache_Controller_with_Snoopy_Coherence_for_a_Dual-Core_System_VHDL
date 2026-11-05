#include "player.hpp"

#include <algorithm>

void Player::reset(int stepCount)
{
    count_ = stepCount;
    current_ = 0;
    playing_ = false;
    scrollRequested_ = true;
}

void Player::goTo(int step)
{
    if(count_ == 0)
        return;
    int target = std::clamp(step, 0, count_ - 1);
    if(target != current_)
        scrollRequested_ = true;
    current_ = target;
}

void Player::togglePlay(double now)
{
    playing_ = !playing_;
    lastTick_ = now;
}

void Player::update(double now)
{
    if(!playing_ || count_ == 0)
        return;
    if(now - lastTick_ < 1.0 / stepsPerSecond)
        return;
    lastTick_ = now;
    if(current_ + 1 >= count_)
        playing_ = false;
    else
        next();
}

bool Player::takeScrollRequest()
{
    bool requested = scrollRequested_;
    scrollRequested_ = false;
    return requested;
}
