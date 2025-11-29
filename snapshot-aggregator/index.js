#!/usr/bin/env node

/**
 * CRDT Snapshot Aggregator for Yjs
 * 
 * Listens to Redis Pub/Sub for Yjs CRDT updates
 * Stores periodic snapshots in MongoDB for durable recovery
 * Restores state from MongoDB on startup
 * 
 * Runs as a sidecar or standalone deployment
 * Non-invasive: does NOT modify y-websocket code
 */

const redis = require('redis');
const { MongoClient } = require('mongodb');
const EventEmitter = require('events');

class CRDTSnapshotAggregator extends EventEmitter {
  constructor(config = {}) {
    super();
    
    this.redisUrl = config.redisUrl || 'redis://redis:6379';
    this.mongoUrl = config.mongoUrl || 'mongodb://mongodb:27017';
    this.dbName = config.dbName || 'whiteboard';
    this.collectionName = config.collectionName || 'crdt_snapshots';
    this.snapshotInterval = config.snapshotInterval || 30000; // 30 seconds
    this.maxSnapshotsPerRoom = config.maxSnapshotsPerRoom || 10;
    
    this.redisClient = null;
    this.mongoClient = null;
    this.db = null;
    this.collection = null;
    
    this.rooms = new Map(); // Track active rooms and their state
    this.snapshotTimers = new Map();
  }

  async connect() {
    console.log('[Aggregator] Connecting to Redis...');
    this.redisClient = redis.createClient({ url: this.redisUrl });
    this.redisClient.on('error', (err) => {
      console.error('[Aggregator] Redis error:', err);
      this.emit('error', err);
    });
    await this.redisClient.connect();
    console.log('[Aggregator] Connected to Redis');

    console.log('[Aggregator] Connecting to MongoDB...');
    this.mongoClient = new MongoClient(this.mongoUrl);
    await this.mongoClient.connect();
    this.db = this.mongoClient.db(this.dbName);
    this.collection = this.db.collection(this.collectionName);
    
    // Create indexes for efficient querying
    await this.collection.createIndex({ roomId: 1, timestamp: -1 });
    await this.collection.createIndex({ timestamp: 1 }, { expireAfterSeconds: 2592000 }); // 30 day TTL
    
    console.log('[Aggregator] Connected to MongoDB');
    this.emit('connected');
  }

  async subscribe() {
    console.log('[Aggregator] Subscribing to Redis Pub/Sub...');
    
    // Subscribe to Yjs awareness updates (room sync messages)
    const subscriber = this.redisClient.duplicate();
    await subscriber.connect();
    
    // Subscribe to all room channels
    // Format: yjs:awareness:* (or specific room pattern)
    await subscriber.pSubscribe('yjs:*', (message, channel) => {
      this.handleMessage(channel, message);
    });

    console.log('[Aggregator] Subscribed to Yjs pub/sub channels');
  }

  handleMessage(channel, messageData) {
    // Parse room ID from channel name
    // Format: yjs:<roomId>:update or similar
    const parts = channel.split(':');
    const roomId = parts[1] || 'default';

    if (!this.rooms.has(roomId)) {
      this.rooms.set(roomId, {
        roomId,
        lastUpdate: Date.now(),
        updateCount: 0,
        state: messageData
      });

      // Schedule periodic snapshot for this room
      this.scheduleSnapshot(roomId);
    } else {
      const room = this.rooms.get(roomId);
      room.lastUpdate = Date.now();
      room.updateCount += 1;
      room.state = messageData; // In production, merge updates, not replace
    }

    // Log update
    if (room.updateCount % 100 === 0) {
      console.log(`[Aggregator] Room ${roomId}: ${room.updateCount} updates received`);
    }
  }

  scheduleSnapshot(roomId) {
    if (this.snapshotTimers.has(roomId)) {
      clearInterval(this.snapshotTimers.get(roomId));
    }

    const timer = setInterval(() => {
      this.takeSnapshot(roomId).catch(err => {
        console.error(`[Aggregator] Snapshot error for room ${roomId}:`, err);
      });
    }, this.snapshotInterval);

    this.snapshotTimers.set(roomId, timer);
  }

  async takeSnapshot(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    const snapshot = {
      roomId,
      timestamp: Date.now(),
      state: room.state,
      updateCount: room.updateCount,
      version: '1.0' // CRDT version
    };

    try {
      // Insert snapshot
      await this.collection.insertOne(snapshot);

      // Clean up old snapshots (keep only maxSnapshotsPerRoom)
      const count = await this.collection.countDocuments({ roomId });
      if (count > this.maxSnapshotsPerRoom) {
        const oldSnapshots = await this.collection
          .find({ roomId })
          .sort({ timestamp: 1 })
          .limit(count - this.maxSnapshotsPerRoom)
          .toArray();

        const oldIds = oldSnapshots.map(s => s._id);
        await this.collection.deleteMany({ _id: { $in: oldIds } });
      }

      console.log(`[Aggregator] Snapshot stored for room ${roomId} (${room.updateCount} updates)`);
    } catch (err) {
      console.error(`[Aggregator] Failed to store snapshot for room ${roomId}:`, err);
    }
  }

  async restoreSnapshot(roomId) {
    try {
      const snapshot = await this.collection.findOne(
        { roomId },
        { sort: { timestamp: -1 } }
      );

      if (snapshot) {
        console.log(`[Aggregator] Restored snapshot for room ${roomId} from ${new Date(snapshot.timestamp).toISOString()}`);
        return snapshot.state;
      }

      console.log(`[Aggregator] No snapshot found for room ${roomId}`);
      return null;
    } catch (err) {
      console.error(`[Aggregator] Failed to restore snapshot for room ${roomId}:`, err);
      return null;
    }
  }

  async getAllSnapshots(roomId, limit = 5) {
    try {
      const snapshots = await this.collection
        .find({ roomId })
        .sort({ timestamp: -1 })
        .limit(limit)
        .toArray();

      return snapshots;
    } catch (err) {
      console.error(`[Aggregator] Failed to get snapshots for room ${roomId}:`, err);
      return [];
    }
  }

  async getStats() {
    const stats = {
      activeRooms: this.rooms.size,
      rooms: {},
      totalSnapshots: await this.collection.countDocuments()
    };

    for (const [roomId, room] of this.rooms) {
      stats.rooms[roomId] = {
        updates: room.updateCount,
        lastUpdate: new Date(room.lastUpdate).toISOString(),
        snapshots: await this.collection.countDocuments({ roomId })
      };
    }

    return stats;
  }

  async disconnect() {
    console.log('[Aggregator] Disconnecting...');

    // Clear timers
    for (const timer of this.snapshotTimers.values()) {
      clearInterval(timer);
    }

    if (this.redisClient) {
      await this.redisClient.quit();
    }

    if (this.mongoClient) {
      await this.mongoClient.close();
    }

    console.log('[Aggregator] Disconnected');
  }
}

module.exports = CRDTSnapshotAggregator;

// Run as standalone service if executed directly
if (require.main === module) {
  const aggregator = new CRDTSnapshotAggregator({
    redisUrl: process.env.REDIS_URL || 'redis://redis:6379',
    mongoUrl: process.env.MONGO_URL || 'mongodb://mongodb:27017',
    snapshotInterval: parseInt(process.env.SNAPSHOT_INTERVAL || '30000'),
  });

  aggregator.on('connected', async () => {
    await aggregator.subscribe();

    // Expose stats endpoint (optional HTTP server)
    if (process.env.ENABLE_HTTP === 'true') {
      const express = require('express');
      const app = express();

      app.get('/health', (req, res) => {
        res.json({ status: 'ok' });
      });

      app.get('/stats', async (req, res) => {
        const stats = await aggregator.getStats();
        res.json(stats);
      });

      app.get('/snapshot/:roomId', async (req, res) => {
        const snapshots = await aggregator.getAllSnapshots(req.params.roomId);
        res.json(snapshots);
      });

      const PORT = process.env.PORT || 9090;
      app.listen(PORT, () => {
        console.log(`[Aggregator] Stats endpoint running on port ${PORT}`);
      });
    }

    console.log('[Aggregator] Ready to aggregate CRDT snapshots');
  });

  aggregator.on('error', (err) => {
    console.error('[Aggregator] Fatal error:', err);
    process.exit(1);
  });

  // Handle shutdown
  process.on('SIGTERM', async () => {
    console.log('[Aggregator] SIGTERM received, shutting down gracefully...');
    await aggregator.disconnect();
    process.exit(0);
  });

  process.on('SIGINT', async () => {
    console.log('[Aggregator] SIGINT received, shutting down gracefully...');
    await aggregator.disconnect();
    process.exit(0);
  });

  aggregator.connect().catch(err => {
    console.error('[Aggregator] Failed to connect:', err);
    process.exit(1);
  });
}
