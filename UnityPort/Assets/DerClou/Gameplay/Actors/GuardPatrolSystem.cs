namespace DerClou.Gameplay.Actors
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Core.Time;
    using DerClou.Core.Navigation;
    using UnityEngine;
    using System.Collections.Generic;

    public class GuardPatrolSystem : MonoBehaviour
    {
        [Header("References")]
        public MissionClock missionClock;
        public BakedNavigationMesh navMesh;

        private Dictionary<int, GuardComponent> guards = new();
        private Dictionary<int, ActorView> entities = new();
        private Dictionary<int, PatrolRoute> routes = new();

        public void RegisterGuard(int actorId, ActorView entity, GuardComponent guard, PatrolRoute route)
        {
            guards[actorId] = guard;
            entities[actorId] = entity;
            routes[actorId] = route;
        }

        private void Update()
        {
            if (missionClock == null || missionClock.IsPaused) return;
            float dt = missionClock.DeltaTime;
            if (dt <= 0f) return;

            foreach (var kv in guards)
            {
                int id = kv.Key;
                var guard = kv.Value;
                var entity = entities.GetValueOrDefault(id);
                var route = routes.GetValueOrDefault(id);
                if (entity == null || route == null || route.nodes.Length == 0) continue;

                TickGuard(id, guard, entity, route, dt);
            }
        }

        private void TickGuard(int id, GuardComponent guard, ActorView entity, PatrolRoute route, float dt)
        {
            var node = route.GetNode(guard.currentNodeIndex);
            Vector3 targetPos = new Vector3(node.position.x, 0, node.position.z);
            Vector3 currentPos = entity.transform.position;

            // Planar distance, not `Vector3.Distance`: authored node
            // positions carry Y=0, but the agent's own Y tracks whatever
            // height the navmesh surface (or a baseOffset quirk) puts it at.
            // Comparing full 3D distance made "arrived" unreachable whenever
            // that Y gap alone exceeded `arrivalTol` — the guard would just
            // walk up to the node and stand there forever, never advancing.
            float dist = Vector2.Distance(
                new Vector2(currentPos.x, currentPos.z),
                new Vector2(targetPos.x, targetPos.z));
            float arrivalTol = 0.2f;

            switch (guard.state)
            {
                case GuardComponent.State.Moving:
                    entity.SetDestination(targetPos);
                    entity.UpdateAnimation(entity.CurrentSpeed);

                    if (dist <= arrivalTol)
                    {
                        entity.Stop();
                        entity.UpdateAnimation(0f);
                        guard.state = GuardComponent.State.Waiting;
                        guard.nodeArrivalTime = missionClock.CurrentTime;
                        if (node.facingYaw >= 0f)
                            entity.SetFacingYaw(node.facingYaw);
                    }
                    break;

                case GuardComponent.State.Waiting:
                    float waited = missionClock.CurrentTime - guard.nodeArrivalTime;
                    if (waited >= node.waitDuration)
                    {
                        guard.currentNodeIndex = (guard.currentNodeIndex + 1) % route.nodes.Length;
                        guard.state = GuardComponent.State.Moving;
                    }
                    break;

                case GuardComponent.State.Acting:
                    // TODO: handle interaction actions at nodes
                    break;

                case GuardComponent.State.Alert:
                    // TODO: alert behavior
                    break;
            }
        }
    }
}