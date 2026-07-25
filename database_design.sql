  -- =====================================================================
-- Tunga (Agakbay) — Relational Database Design (MySQL 8.0+)
-- Derived from the current Firestore/Firebase data model:
--   ERD.txt, firestore.rules, functions/index.js,
--   lib/services/offline_activity_database.dart,
--   lib/services/hike_room_service.dart, lib/services/auth_database_service.dart
--
-- Notes on translation choices:
--  - Firestore auto-IDs / Firebase UIDs -> VARCHAR primary keys.
--  - Firestore subcollections -> child tables with a FK back to the parent.
--  - Firestore array fields (routePoints, stations, completedTrailKeys)
--    -> normalized child tables (keeps things queryable/indexable in SQL).
--  - Denormalized "snapshot" fields Firestore stored for convenience
--    (authorName, guideName, senderName, etc.) are preserved as-is,
--    since the app reads them without a join today.
--  - InnoDB + utf8mb4 throughout for FK support and full Unicode.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. USERS
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id                      VARCHAR(128)  NOT NULL,          -- Firebase UID (or app-generated)
  full_name               VARCHAR(255)  NOT NULL,
  display_name            VARCHAR(255)  NULL,
  username                VARCHAR(100)  NOT NULL,
  email                   VARCHAR(255)  NOT NULL,
  password_hash           VARCHAR(255)  NULL,              -- only needed if auth moves off Firebase Auth
  account_type            ENUM('hiker','tour_guide') NOT NULL,
  role                    VARCHAR(50)   NOT NULL,
  guide_verified          BOOLEAN       NULL,               -- only meaningful for tour_guide accounts
  email_verified          BOOLEAN       NOT NULL DEFAULT FALSE,
  email_verified_custom   BOOLEAN       NOT NULL DEFAULT FALSE,
  verification_method     ENUM('link','code') NOT NULL DEFAULT 'link',
  verified_at             DATETIME      NULL,
  profile_photo_url       VARCHAR(500)  NULL,
  emergency_contact_name  VARCHAR(255)  NULL,
  emergency_contact_phone VARCHAR(50)   NULL,
  active_hike_room_id     VARCHAR(64)   NULL,               -- FK added after hike_rooms exists
  created_at              DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at              DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                        ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_username (username),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 2. EMAIL VERIFICATIONS  (6-digit code flow, functions/index.js)
-- ---------------------------------------------------------------------
CREATE TABLE email_verifications (
  user_id     VARCHAR(128) NOT NULL,
  email       VARCHAR(255) NOT NULL,
  code_hash   CHAR(64)     NOT NULL,          -- sha256(uid:code)
  attempts    INT          NOT NULL DEFAULT 0,
  expires_at  DATETIME(3)  NOT NULL,
  resend_at   DATETIME(3)  NOT NULL,
  created_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                           ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (user_id),
  CONSTRAINT fk_email_verifications_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 3. NOTIFICATIONS  (users/{userId}/notifications)
-- ---------------------------------------------------------------------
CREATE TABLE notifications (
  id                BIGINT UNSIGNED AUTO_INCREMENT,
  user_id           VARCHAR(128) NOT NULL,
  type              VARCHAR(50)  NOT NULL,     -- e.g. 'trail', 'comment'
  title             VARCHAR(255) NOT NULL,
  body              TEXT         NOT NULL,
  related_post_id   VARCHAR(64)  NULL,
  related_mountain_key VARCHAR(128) NULL,
  is_read           BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_notifications_user_created (user_id, created_at DESC),
  CONSTRAINT fk_notifications_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 4. OFFLINE ACTIVITIES  (users/{userId}/offline_activities, mirrors sqflite)
-- ---------------------------------------------------------------------
CREATE TABLE offline_activities (
  id                       VARCHAR(64)  NOT NULL,   -- local activity id
  sync_key                 VARCHAR(64)  NOT NULL,
  user_id                  VARCHAR(128) NOT NULL,
  activity_type            VARCHAR(50)  NOT NULL,
  status                   ENUM('recording','paused','finished') NOT NULL,
  started_at               DATETIME(3)  NOT NULL,
  ended_at                 DATETIME(3)  NULL,
  duration_seconds         INT          NOT NULL DEFAULT 0,
  moving_duration_seconds  INT          NOT NULL DEFAULT 0,
  distance_meters          DECIMAL(10,2) NOT NULL DEFAULT 0,
  elevation_gain_meters    DECIMAL(10,2) NOT NULL DEFAULT 0,
  average_speed_mps        DECIMAL(6,3) NOT NULL DEFAULT 0,
  point_count              INT          NOT NULL DEFAULT 0,
  upload_complete          BOOLEAN      NOT NULL DEFAULT FALSE,
  updated_at               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                        ON UPDATE CURRENT_TIMESTAMP(3),
  synced_at                DATETIME(3)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_offline_activities_sync_key (sync_key),
  KEY idx_offline_activities_user (user_id, started_at DESC),
  CONSTRAINT fk_offline_activities_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 5. ACTIVITY POINTS  (users/{userId}/offline_activities/{syncKey}/points)
-- ---------------------------------------------------------------------
CREATE TABLE activity_points (
  id                          BIGINT UNSIGNED AUTO_INCREMENT,
  activity_id                 VARCHAR(64) NOT NULL,
  latitude                    DECIMAL(10,7) NOT NULL,
  longitude                   DECIMAL(10,7) NOT NULL,
  point_timestamp              DATETIME(3)  NOT NULL,
  altitude_meters              DECIMAL(8,2) NULL,
  accuracy_meters               DECIMAL(8,2) NULL,
  speed_mps                    DECIMAL(6,3) NULL,
  distance_from_start_meters    DECIMAL(10,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_activity_points_activity_time (activity_id, point_timestamp),
  CONSTRAINT fk_activity_points_activity
    FOREIGN KEY (activity_id) REFERENCES offline_activities(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 6. HIKE ROOMS
-- ---------------------------------------------------------------------
CREATE TABLE hike_rooms (
  id                  VARCHAR(64)  NOT NULL,
  room_code           CHAR(6)      NOT NULL,
  mountain_name       VARCHAR(255) NOT NULL,
  mountain_place_id   VARCHAR(255) NULL,
  mountain_latitude   DECIMAL(9,6) NOT NULL,
  mountain_longitude  DECIMAL(9,6) NOT NULL,
  route_name          VARCHAR(255) NOT NULL DEFAULT 'Shared trail route',
  jump_off_label      VARCHAR(255) NULL,
  route_asset_path    VARCHAR(500) NULL,
  guide_id            VARCHAR(128) NOT NULL,
  guide_name          VARCHAR(255) NOT NULL,       -- denormalized snapshot
  status              ENUM('waiting','active','ended') NOT NULL DEFAULT 'waiting',
  created_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                   ON UPDATE CURRENT_TIMESTAMP(3),
  started_at          DATETIME(3)  NULL,
  ended_at            DATETIME(3)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_hike_rooms_room_code (room_code),
  KEY idx_hike_rooms_guide (guide_id),
  CONSTRAINT fk_hike_rooms_guide
    FOREIGN KEY (guide_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- now that hike_rooms exists, wire up users.active_hike_room_id
ALTER TABLE users
  ADD CONSTRAINT fk_users_active_hike_room
    FOREIGN KEY (active_hike_room_id) REFERENCES hike_rooms(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------
-- 7. HIKE ROOM ROUTE POINTS  (hike_rooms.routePoints array)
-- ---------------------------------------------------------------------
CREATE TABLE hike_room_route_points (
  id            BIGINT UNSIGNED AUTO_INCREMENT,
  hike_room_id  VARCHAR(64) NOT NULL,
  seq_order     INT NOT NULL,
  latitude      DECIMAL(9,6) NOT NULL,
  longitude     DECIMAL(9,6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_hike_room_points_order (hike_room_id, seq_order),
  CONSTRAINT fk_hike_room_points_room
    FOREIGN KEY (hike_room_id) REFERENCES hike_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 8. HIKE ROOM PARTICIPANTS  (hike_rooms/{roomId}/participants)
-- ---------------------------------------------------------------------
CREATE TABLE hike_room_participants (
  id                    BIGINT UNSIGNED AUTO_INCREMENT,
  hike_room_id          VARCHAR(64)  NOT NULL,
  user_id               VARCHAR(128) NOT NULL,
  name                  VARCHAR(255) NOT NULL,   -- denormalized snapshot
  role                  ENUM('tour_guide','hiker') NOT NULL,
  device_status         VARCHAR(50)  NOT NULL DEFAULT 'not_connected',
  membership_status     ENUM('active','left','removed','room_ended') NOT NULL DEFAULT 'active',
  activity_status       VARCHAR(50)  NOT NULL DEFAULT 'in_room',  -- 'in_room' | 'hiking'
  joined_at             DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  left_at               DATETIME(3)  NULL,
  hiking_started_at     DATETIME(3)  NULL,
  returned_to_room_at   DATETIME(3)  NULL,
  removed_by            VARCHAR(128) NULL,
  removed_at            DATETIME(3)  NULL,
  updated_at            DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                     ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_hike_room_participants_room_user (hike_room_id, user_id),
  KEY idx_hike_room_participants_user (user_id),
  CONSTRAINT fk_hike_room_participants_room
    FOREIGN KEY (hike_room_id) REFERENCES hike_rooms(id) ON DELETE CASCADE,
  CONSTRAINT fk_hike_room_participants_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_hike_room_participants_removed_by
    FOREIGN KEY (removed_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 9. SOS EVENTS  (hike_rooms/{roomId}/sos_events)
-- ---------------------------------------------------------------------
CREATE TABLE sos_events (
  id                VARCHAR(64)  NOT NULL,
  hike_room_id      VARCHAR(64)  NOT NULL,
  room_code         CHAR(6)      NOT NULL,       -- denormalized snapshot
  sender_id         VARCHAR(128) NOT NULL,
  sender_name       VARCHAR(255) NOT NULL,       -- denormalized snapshot
  latitude          DECIMAL(9,6) NOT NULL,
  longitude         DECIMAL(9,6) NOT NULL,
  transport         VARCHAR(50)  NOT NULL DEFAULT 'internet',
  status            ENUM('sent','acknowledged') NOT NULL DEFAULT 'sent',
  acknowledged_by   VARCHAR(128) NULL,
  acknowledged_at   DATETIME(3)  NULL,
  created_at        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                 ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_sos_events_room_created (hike_room_id, created_at DESC),
  CONSTRAINT fk_sos_events_room
    FOREIGN KEY (hike_room_id) REFERENCES hike_rooms(id) ON DELETE CASCADE,
  CONSTRAINT fk_sos_events_sender
    FOREIGN KEY (sender_id) REFERENCES users(id),
  CONSTRAINT fk_sos_events_acknowledged_by
    FOREIGN KEY (acknowledged_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 10. COMMUNITY POSTS
-- ---------------------------------------------------------------------
CREATE TABLE community_posts (
  id             VARCHAR(64)  NOT NULL,
  author_id      VARCHAR(128) NOT NULL,
  author_name    VARCHAR(255) NOT NULL,   -- denormalized snapshot
  content        TEXT         NOT NULL,
  mountain_name  VARCHAR(255) NULL,
  like_count     INT UNSIGNED NOT NULL DEFAULT 0,
  comment_count  INT UNSIGNED NOT NULL DEFAULT 0,
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                              ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_community_posts_author (author_id, created_at DESC),
  CONSTRAINT fk_community_posts_author
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 11. POST LIKES  (community_posts/{postId}/likes)
-- ---------------------------------------------------------------------
CREATE TABLE post_likes (
  post_id     VARCHAR(64)  NOT NULL,
  user_id     VARCHAR(128) NOT NULL,
  created_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (post_id, user_id),
  CONSTRAINT fk_post_likes_post
    FOREIGN KEY (post_id) REFERENCES community_posts(id) ON DELETE CASCADE,
  CONSTRAINT fk_post_likes_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 12. POST COMMENTS  (community_posts/{postId}/comments)
-- ---------------------------------------------------------------------
CREATE TABLE post_comments (
  id           VARCHAR(64)  NOT NULL,
  post_id      VARCHAR(64)  NOT NULL,
  author_id    VARCHAR(128) NOT NULL,
  author_name  VARCHAR(255) NOT NULL,   -- denormalized snapshot
  content      TEXT         NOT NULL,
  created_at   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_post_comments_post_created (post_id, created_at),
  CONSTRAINT fk_post_comments_post
    FOREIGN KEY (post_id) REFERENCES community_posts(id) ON DELETE CASCADE,
  CONSTRAINT fk_post_comments_author
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 13. LEADERBOARD STATS  (1:1 with users)
-- ---------------------------------------------------------------------
CREATE TABLE leaderboard_stats (
  user_id               VARCHAR(128) NOT NULL,
  display_name          VARCHAR(255) NOT NULL,   -- denormalized snapshot
  account_type          ENUM('hiker','tour_guide') NOT NULL,
  completed_mountains   INT UNSIGNED NOT NULL DEFAULT 0,
  summits_reached       INT UNSIGNED NOT NULL DEFAULT 0,
  total_distance_km     DECIMAL(10,2) NOT NULL DEFAULT 0,
  last_mountain_name    VARCHAR(255) NULL,
  last_mountain_key     VARCHAR(128) NULL,
  updated_at            DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                     ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (user_id),
  KEY idx_leaderboard_distance (total_distance_km DESC),
  CONSTRAINT fk_leaderboard_stats_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 14. LEADERBOARD COMPLETED TRAILS  (leaderboard.completedTrailKeys array)
-- ---------------------------------------------------------------------
CREATE TABLE leaderboard_completed_trails (
  user_id       VARCHAR(128) NOT NULL,
  mountain_key  VARCHAR(128) NOT NULL,
  PRIMARY KEY (user_id, mountain_key),
  CONSTRAINT fk_leaderboard_trails_user
    FOREIGN KEY (user_id) REFERENCES leaderboard_stats(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 15. APP CONTENT  (static/editorial content, e.g. safety guides)
-- ---------------------------------------------------------------------
CREATE TABLE app_content (
  id          VARCHAR(64) NOT NULL,
  body        LONGTEXT     NULL,
  sections    JSON         NULL,
  created_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                           ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 16. TRAIL SUBMISSIONS  (community-recorded trail data)
-- ---------------------------------------------------------------------
CREATE TABLE trail_submissions (
  id            VARCHAR(64)  NOT NULL,
  submitted_by  VARCHAR(128) NOT NULL,
  mountain_key  VARCHAR(128) NOT NULL,
  mountain_name VARCHAR(255) NULL,
  trail_name    VARCHAR(255) NULL,
  status        ENUM('pending','included') NOT NULL DEFAULT 'pending',
  recorded_at   DATETIME(3)  NULL,
  processed_at  DATETIME(3)  NULL,
  payload       JSON         NULL,          -- catch-all for extra route payload fields
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                             ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_trail_submissions_user (submitted_by, created_at DESC),
  KEY idx_trail_submissions_mountain (mountain_key),
  CONSTRAINT fk_trail_submissions_user
    FOREIGN KEY (submitted_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 17. TRAIL SUBMISSION ROUTE POINTS
-- ---------------------------------------------------------------------
CREATE TABLE trail_submission_points (
  id                     BIGINT UNSIGNED AUTO_INCREMENT,
  trail_submission_id    VARCHAR(64) NOT NULL,
  seq_order              INT NOT NULL,
  latitude               DECIMAL(9,7) NOT NULL,
  longitude              DECIMAL(9,7) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_trail_submission_points_order (trail_submission_id, seq_order),
  CONSTRAINT fk_trail_submission_points_submission
    FOREIGN KEY (trail_submission_id) REFERENCES trail_submissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 18. MOUNTAIN TRAILS  (verified/public trail data source)
-- ---------------------------------------------------------------------
CREATE TABLE mountain_trails (
  id                            VARCHAR(128) NOT NULL,   -- mountain_key
  trail_name                    VARCHAR(255) NOT NULL,
  status                        ENUM('verified','draft') NOT NULL DEFAULT 'verified',
  source                        VARCHAR(50)  NOT NULL DEFAULT 'community_recorded',
  generated_from_submission_id  VARCHAR(64)  NULL,
  recorded_at                   DATETIME(3)  NULL,
  created_at                    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at                    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                              ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  CONSTRAINT fk_mountain_trails_submission
    FOREIGN KEY (generated_from_submission_id) REFERENCES trail_submissions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 19. MOUNTAIN TRAIL ROUTE POINTS  (mountain_trails.routePoints array)
-- ---------------------------------------------------------------------
CREATE TABLE mountain_trail_points (
  id                 BIGINT UNSIGNED AUTO_INCREMENT,
  mountain_trail_id  VARCHAR(128) NOT NULL,
  seq_order          INT NOT NULL,
  latitude           DECIMAL(9,7) NOT NULL,
  longitude          DECIMAL(9,7) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mountain_trail_points_order (mountain_trail_id, seq_order),
  CONSTRAINT fk_mountain_trail_points_trail
    FOREIGN KEY (mountain_trail_id) REFERENCES mountain_trails(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 20. MOUNTAIN TRAIL STATIONS  (mountain_trails.stations array)
-- ---------------------------------------------------------------------
CREATE TABLE mountain_trail_stations (
  id                 BIGINT UNSIGNED AUTO_INCREMENT,
  mountain_trail_id  VARCHAR(128) NOT NULL,
  seq_order          INT NOT NULL,
  name               VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mountain_trail_stations_order (mountain_trail_id, seq_order),
  CONSTRAINT fk_mountain_trail_stations_trail
    FOREIGN KEY (mountain_trail_id) REFERENCES mountain_trails(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 21. PENDING TRAIL SUBMISSIONS  (device-local outbox, mirrors sqflite)
--     Only relevant if the offline queue itself is centralized server-side;
--     otherwise this table stays client-only (SQLite) and is omitted here.
-- ---------------------------------------------------------------------
-- CREATE TABLE pending_trail_submissions (
--   id           VARCHAR(64) NOT NULL,
--   user_id      VARCHAR(128) NOT NULL,
--   payload_json JSON NOT NULL,
--   created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
--   synced       BOOLEAN NOT NULL DEFAULT FALSE,
--   synced_at    DATETIME(3) NULL,
--   PRIMARY KEY (id)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
