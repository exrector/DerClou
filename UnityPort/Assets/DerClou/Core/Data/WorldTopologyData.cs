namespace DerClou.Core.Data
{
    [System.Serializable]
    public struct RoomSpec
    {
        public string id;
        public WorldBox bounds;
    }

    [System.Serializable]
    public struct PortalSpec
    {
        public string id;
        public string roomAId;
        public string roomBId;
        public string doorId;
        public WorldPoint position;
        public float width;
        public float baseCost;
    }
}
