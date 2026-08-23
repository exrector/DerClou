namespace DerClou.Core.Systems
{
    using System;
    using System.Collections.Generic;
    using DerClou.Core.Simulation;

    /// <summary>
    /// Advances every security camera's scan yaw by one fixed step. Pure C#
    /// port of the old <c>SecurityCamera.Update()</c> — same formula
    /// (<c>scanPhase += dt / scanPeriod</c>, yaw = sine sweep across
    /// <c>scanArc</c>), now against <see cref="CameraState"/> and a step
    /// size <see cref="SimulationStep"/> controls instead of
    /// <c>Time.deltaTime</c>. See `docs/U2_SIMULATION_DESIGN.md` step 2c.
    /// </summary>
    public static class SecurityCameraSystem
    {
        public static void Tick(MissionState state, float dt)
        {
            var ids = new List<string>(state.Cameras.Keys);
            foreach (var id in ids)
            {
                var cam = state.Cameras[id];
                // Unpowered cameras freeze at their last yaw rather than
                // resetting or continuing to scan — matches the old
                // MonoBehaviour's `if (!Powered) return;` exactly.
                if (cam.powered)
                {
                    cam.scanPhase += dt / cam.scanPeriod;
                    cam.currentYaw = MathF.Sin(cam.scanPhase * MathF.PI * 2f) * cam.scanArc * 0.5f;
                }
                state.Cameras[id] = cam;
            }
        }
    }
}
