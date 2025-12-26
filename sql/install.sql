-- DPS Airlines Database Schema

CREATE TABLE IF NOT EXISTS `airline_flights` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_number` VARCHAR(10) NOT NULL,
    `pilot_citizenid` VARCHAR(50) NOT NULL,
    `from_airport` VARCHAR(50) NOT NULL,
    `to_airport` VARCHAR(50) NOT NULL,
    `flight_type` ENUM('passenger', 'cargo', 'charter') NOT NULL DEFAULT 'passenger',
    `plane_model` VARCHAR(50) NOT NULL,
    `passengers` INT DEFAULT 0,
    `cargo_weight` INT DEFAULT 0,
    `status` ENUM('scheduled', 'boarding', 'departed', 'arrived', 'cancelled', 'crashed') DEFAULT 'scheduled',
    `payment` INT DEFAULT 0,
    `started_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_pilot` (`pilot_citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `airline_pilot_stats` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `total_flights` INT DEFAULT 0,
    `total_passengers` INT DEFAULT 0,
    `total_cargo` INT DEFAULT 0,
    `total_earnings` INT DEFAULT 0,
    `flight_hours` DECIMAL(10,2) DEFAULT 0,
    `reputation` INT DEFAULT 0,
    `license_obtained` TIMESTAMP NULL,
    `lessons_completed` TEXT DEFAULT '[]',
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `airline_maintenance` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `plane_model` VARCHAR(50) NOT NULL,
    `flights_since_service` INT DEFAULT 0,
    `last_service` TIMESTAMP NULL,
    `service_history` TEXT DEFAULT '[]',
    `owned_by` VARCHAR(50) DEFAULT 'company', -- citizenid or 'company'
    INDEX `idx_plane` (`plane_model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `airline_charters` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `client_citizenid` VARCHAR(50) NOT NULL,
    `pilot_citizenid` VARCHAR(50) NULL,
    `pickup_coords` TEXT NOT NULL,
    `dropoff_coords` TEXT NOT NULL,
    `status` ENUM('pending', 'accepted', 'inprogress', 'completed', 'cancelled') DEFAULT 'pending',
    `fee` INT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL,
    INDEX `idx_client` (`client_citizenid`),
    INDEX `idx_pilot` (`pilot_citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `airline_dispatch` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_type` ENUM('passenger', 'cargo') NOT NULL,
    `from_airport` VARCHAR(50) NOT NULL,
    `to_airport` VARCHAR(50) NOT NULL,
    `priority` ENUM('low', 'normal', 'high', 'urgent') DEFAULT 'normal',
    `plane_required` VARCHAR(50) NULL,
    `passengers` INT DEFAULT 0,
    `cargo_weight` INT DEFAULT 0,
    `cargo_type` VARCHAR(50) NULL,
    `assigned_to` VARCHAR(50) NULL,
    `payment` INT NOT NULL,
    `expires_at` TIMESTAMP NULL,
    `status` ENUM('available', 'assigned', 'completed', 'expired') DEFAULT 'available',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_status` (`status`),
    INDEX `idx_assigned` (`assigned_to`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Black Box Flight Recorder
CREATE TABLE IF NOT EXISTS `airline_blackbox` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_number` VARCHAR(10) NOT NULL,
    `pilot_citizenid` VARCHAR(50) NOT NULL,
    `start_time` TIMESTAMP NULL,
    `end_time` TIMESTAMP NULL,
    `telemetry_count` INT DEFAULT 0,
    `events_count` INT DEFAULT 0,
    `data_summary` TEXT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_flight` (`flight_number`),
    INDEX `idx_pilot` (`pilot_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Crash Records
CREATE TABLE IF NOT EXISTS `airline_crashes` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `flight_number` VARCHAR(10) NOT NULL,
    `pilot_citizenid` VARCHAR(50) NOT NULL,
    `flight_id` INT NULL,
    `crash_coords` TEXT NULL,
    `crash_phase` VARCHAR(50) NULL,
    `crash_time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `investigation_notes` TEXT NULL,
    INDEX `idx_pilot` (`pilot_citizenid`),
    INDEX `idx_flight` (`flight_id`),
    FOREIGN KEY (`flight_id`) REFERENCES `airline_flights`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Checkride Records (for recurrent training)
CREATE TABLE IF NOT EXISTS `airline_checkrides` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `pilot_citizenid` VARCHAR(50) NOT NULL,
    `checkride_type` ENUM('initial', 'recurrent', 'upgrade') NOT NULL DEFAULT 'recurrent',
    `status` ENUM('pending', 'passed', 'failed') DEFAULT 'pending',
    `instructor_citizenid` VARCHAR(50) NULL,
    `score` INT NULL,
    `notes` TEXT NULL,
    `scheduled_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_pilot` (`pilot_citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add crashes column to pilot stats
ALTER TABLE `airline_pilot_stats` ADD COLUMN IF NOT EXISTS `crashes` INT DEFAULT 0;
ALTER TABLE `airline_pilot_stats` ADD COLUMN IF NOT EXISTS `last_flight` TIMESTAMP NULL;
ALTER TABLE `airline_pilot_stats` ADD COLUMN IF NOT EXISTS `checkride_due` TIMESTAMP NULL;

-- Insert default maintenance records for company planes
INSERT IGNORE INTO `airline_maintenance` (`plane_model`, `flights_since_service`, `owned_by`) VALUES
    ('luxor', 0, 'company'),
    ('shamal', 0, 'company'),
    ('nimbus', 0, 'company'),
    ('miljet', 0, 'company');
