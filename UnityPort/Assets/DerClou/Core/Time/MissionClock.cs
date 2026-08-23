namespace DerClou.Core.Time
{
    /// <summary>
    /// Deterministic mission clock. All gameplay timing derives from this.
    /// </summary>
    public class MissionClock
    {
        public float CurrentTime { get; private set; }
        public float DeltaTime { get; private set; }
        public bool IsPaused { get; private set; }

        public event System.Action<float> OnTick;

        public void Tick(float dt)
        {
            if (IsPaused) { DeltaTime = 0f; return; }
            DeltaTime = dt;
            CurrentTime += dt;
            OnTick?.Invoke(dt);
        }

        public void Pause() => IsPaused = true;
        public void Resume() => IsPaused = false;
        public void Reset() { CurrentTime = 0f; DeltaTime = 0f; IsPaused = false; }

        // System.MathF, not UnityEngine.Mathf: Core is pure C# by design (see
        // the port README), so it stays testable and usable outside Unity.
        public float TimeToFrames(float seconds, float fixedDt = 1f / 60f) => System.MathF.Ceiling(seconds / fixedDt) * fixedDt;
    }

    /// <summary>
    /// Fixed-step accumulator for deterministic simulation.
    /// </summary>
    public class FixedStepAccumulator
    {
        public float FixedDt { get; }
        public float Accumulator { get; private set; }

        public FixedStepAccumulator(float fixedDt = 1f / 60f) { FixedDt = fixedDt; }

        public void Accumulate(float dt) => Accumulator += dt;

        public bool TryConsume()
        {
            if (Accumulator >= FixedDt) { Accumulator -= FixedDt; return true; }
            return false;
        }

        public void Reset() => Accumulator = 0f;
    }
}