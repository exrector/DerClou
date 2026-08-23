namespace DerClou.Core.Tests
{
    using DerClou.Core.Data;
    using DerClou.Core.Time;
    using NUnit.Framework;

    public class CharacterProfileTests
    {
        [Test]
        public void StandardProfile_HasExpectedDefaults()
        {
            var p = CharacterProfile.Standard;
            Assert.AreEqual(0.6f, p.width);
            Assert.AreEqual(1.75f, p.height);
            Assert.AreEqual(1.4f, p.walkSpeed);
            Assert.AreEqual(0.3f, p.Radius);
        }

        [Test]
        public void DurationForDistance_ComputesCorrectly()
        {
            var p = CharacterProfile.Standard;
            Assert.AreEqual(1f, p.DurationForDistance(1.4f), 0.001f);
            Assert.AreEqual(2f, p.DurationForDistance(2.8f), 0.001f);
            Assert.IsTrue(float.IsPositiveInfinity(p.DurationForDistance(10f)) == false);
        }

        [Test]
        public void NavigationProfile_PicksWidestAndTallest()
        {
            var p1 = new CharacterProfile { width = 0.5f, height = 1.7f, walkSpeed = 1.4f };
            var p2 = new CharacterProfile { width = 0.7f, height = 1.9f, walkSpeed = 1.2f };
            var nav = CharacterProfile.NavigationProfileFor(new[] { p1, p2 });
            Assert.AreEqual(0.7f, nav.width);
            Assert.AreEqual(1.9f, nav.height);
            Assert.AreEqual(1.4f, nav.walkSpeed); // uses standard speed
        }
    }

    public class MissionClockTests
    {
        [Test]
        public void Tick_AccumulatesTime()
        {
            var clock = new MissionClock();
            clock.Tick(0.5f);
            Assert.AreEqual(0.5f, clock.CurrentTime);
            clock.Tick(0.5f);
            Assert.AreEqual(1.0f, clock.CurrentTime);
        }

        [Test]
        public void Pause_StopsTime()
        {
            var clock = new MissionClock();
            clock.Pause();
            clock.Tick(1f);
            Assert.AreEqual(0f, clock.CurrentTime);
        }

        [Test]
        public void Resume_ContinuesFromPausedTime()
        {
            var clock = new MissionClock();
            clock.Tick(1f);
            clock.Pause();
            clock.Tick(1f);
            clock.Resume();
            clock.Tick(1f);
            Assert.AreEqual(2f, clock.CurrentTime);
        }
    }

    public class FixedStepAccumulatorTests
    {
        [Test]
        public void TryConsume_ReturnsTrue_WhenAccumulated()
        {
            var acc = new FixedStepAccumulator(0.1f);
            acc.Accumulate(0.05f);
            Assert.IsFalse(acc.TryConsume());
            acc.Accumulate(0.1f);
            Assert.IsTrue(acc.TryConsume());
            Assert.AreEqual(0.05f, acc.Accumulator, 0.001f);
        }
    }
}