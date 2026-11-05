#pragma once

class Player
{
  public:
    void reset(int stepCount);
    void goTo(int step);
    void next()
    {
        goTo(current_ + 1);
    }
    void previous()
    {
        goTo(current_ - 1);
    }
    void first()
    {
        goTo(0);
    }
    void last()
    {
        goTo(count_ - 1);
    }

    void togglePlay(double now);
    void update(double now);

    int current() const
    {
        return current_;
    }
    int count() const
    {
        return count_;
    }
    bool isPlaying() const
    {
        return playing_;
    }
    bool takeScrollRequest();

    float stepsPerSecond = 2.0f;

  private:
    int current_ = 0;
    int count_ = 0;
    bool playing_ = false;
    bool scrollRequested_ = true;
    double lastTick_ = 0.0;
};
