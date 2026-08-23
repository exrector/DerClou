namespace DerClou.Core.Data
{
    /// <summary>
    /// Physical and locomotion profile for a character.
    /// Single source of truth for navigation erosion, doorway validation,
    /// collision capsules and walk timing.
    /// </summary>
    [System.Serializable]
    public struct CharacterProfile
    {
        public float width;                      // Shoulder width (meters)
        public float height;                     // Standing height (meters)
        public float walkSpeed;                  // Max comfortable walking speed (m/s)
        public float acceleration;               // m/s²
        public float deceleration;               // m/s²
        public float preferredWallClearance;     // Comfort space from walls (m)
        public float wallAvoidanceWeight;        // Route cost weight for clearance
        public float maxTurnRateDegrees;         // Max turn rate (deg/s)
        public float preferredCornerRadius;      // Corner rounding radius (m)
        public float interactionArrivalTolerance; // Distance to interaction slot (m)

        public float Radius => width * 0.5f;

        public float DurationForDistance(float distance)
            => walkSpeed > 0f ? distance / walkSpeed : float.PositiveInfinity;

        public static CharacterProfile Standard => new CharacterProfile
        {
            width = 0.6f,
            height = 1.75f,
            walkSpeed = 1.4f,
            acceleration = 2.8f,
            deceleration = 3.2f,
            preferredWallClearance = 0.45f,
            wallAvoidanceWeight = 4f,
            maxTurnRateDegrees = 240f,
            preferredCornerRadius = 0.45f,
            interactionArrivalTolerance = 0.08f
        };

        public static CharacterProfile NavigationProfileFor(System.Collections.Generic.IEnumerable<CharacterProfile> profiles)
        {
            var list = new System.Collections.Generic.List<CharacterProfile>(profiles);
            if (list.Count == 0) return Standard;

            float maxW = 0f, maxH = 0f;
            foreach (var p in list) { if (p.width > maxW) maxW = p.width; if (p.height > maxH) maxH = p.height; }
            return new CharacterProfile
            {
                width = maxW,
                height = maxH,
                walkSpeed = Standard.walkSpeed,
                acceleration = Standard.acceleration,
                deceleration = Standard.deceleration,
                preferredWallClearance = Standard.preferredWallClearance,
                wallAvoidanceWeight = Standard.wallAvoidanceWeight,
                maxTurnRateDegrees = Standard.maxTurnRateDegrees,
                preferredCornerRadius = Standard.preferredCornerRadius,
                interactionArrivalTolerance = Standard.interactionArrivalTolerance
            };
        }
    }
}