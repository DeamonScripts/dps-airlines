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

    -- Flight Totals
    `total_flights` INT DEFAULT 0,
    `total_passengers` INT DEFAULT 0,
    `total_cargo` INT DEFAULT 0,
    `total_earnings` INT DEFAULT 0,

    -- Realistic Flight Hours (like a real logbook)
    `total_hours` DECIMAL(10,2) DEFAULT 0,           -- Total flight time
    `pic_hours` DECIMAL(10,2) DEFAULT 0,             -- Pilot in Command hours
    `night_hours` DECIMAL(10,2) DEFAULT 0,           -- Night flying hours
    `ifr_hours` DECIMAL(10,2) DEFAULT 0,             -- Instrument conditions
    `cross_country_hours` DECIMAL(10,2) DEFAULT 0,   -- Flights > 50nm

    -- Landings
    `day_landings` INT DEFAULT 0,
    `night_landings` INT DEFAULT 0,

    -- Job Type Hours
    `passenger_hours` DECIMAL(10,2) DEFAULT 0,
    `cargo_hours` DECIMAL(10,2) DEFAULT 0,
    `charter_hours` DECIMAL(10,2) DEFAULT 0,
    `ferry_hours` DECIMAL(10,2) DEFAULT 0,

    -- Type Ratings (aircraft certifications)
    `type_ratings` TEXT DEFAULT '[]',                -- ["luxor", "shamal", "nimbus"]

    -- Safety Record
    `crashes` INT DEFAULT 0,
    `incidents` INT DEFAULT 0,
    `go_arounds` INT DEFAULT 0,
    `hard_landings` INT DEFAULT 0,

    -- Career
    `reputation` INT DEFAULT 0,
    `license_type` ENUM('student', 'ppl', 'cpl', 'atpl') DEFAULT 'student',
    `license_obtained` TIMESTAMP NULL,
    `medical_expires` TIMESTAMP NULL,
    `lessons_completed` TEXT DEFAULT '[]',
    `last_flight` TIMESTAMP NULL,
    `checkride_due` TIMESTAMP NULL,

    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Detailed Flight Logbook (every flight recorded)
CREATE TABLE IF NOT EXISTS `airline_pilot_logbook` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `flight_id` INT NULL,
    `flight_number` VARCHAR(20) NULL,

    -- Route
    `departure_airport` VARCHAR(50) NOT NULL,
    `arrival_airport` VARCHAR(50) NOT NULL,
    `route_distance` DECIMAL(10,2) DEFAULT 0,       -- km

    -- Aircraft
    `aircraft_model` VARCHAR(50) NOT NULL,
    `aircraft_category` VARCHAR(20) NULL,            -- small, medium, large, executive

    -- Times
    `departure_time` TIMESTAMP NULL,
    `arrival_time` TIMESTAMP NULL,
    `flight_time` DECIMAL(10,2) DEFAULT 0,          -- hours
    `block_time` DECIMAL(10,2) DEFAULT 0,           -- gate-to-gate hours

    -- Conditions
    `day_night` ENUM('day', 'night', 'mixed') DEFAULT 'day',
    `weather_conditions` VARCHAR(50) NULL,
    `ifr_vfr` ENUM('vfr', 'ifr') DEFAULT 'vfr',

    -- Job Type
    `flight_type` ENUM('passenger', 'cargo', 'charter', 'ferry', 'training') NOT NULL,
    `passengers` INT DEFAULT 0,
    `cargo_kg` INT DEFAULT 0,

    -- Performance
    `landings` INT DEFAULT 1,
    `landing_quality` ENUM('smooth', 'normal', 'hard', 'crashed') DEFAULT 'normal',
    `fuel_used` DECIMAL(10,2) DEFAULT 0,

    -- Financial
    `payment` INT DEFAULT 0,
    `fuel_cost` INT DEFAULT 0,
    `net_earnings` INT DEFAULT 0,

    -- Notes
    `remarks` TEXT NULL,
    `status` ENUM('completed', 'cancelled', 'crashed', 'diverted') DEFAULT 'completed',

    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX `idx_pilot` (`citizenid`),
    INDEX `idx_date` (`departure_time`),
    INDEX `idx_type` (`flight_type`),
    FOREIGN KEY (`citizenid`) REFERENCES `airline_pilot_stats`(`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ferry Flight Jobs (repositioning aircraft)
CREATE TABLE IF NOT EXISTS `airline_ferry_jobs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `aircraft_model` VARCHAR(50) NOT NULL,
    `from_airport` VARCHAR(50) NOT NULL,
    `to_airport` VARCHAR(50) NOT NULL,
    `reason` ENUM('new_delivery', 'reposition', 'maintenance', 'lease_return') DEFAULT 'reposition',
    `priority` ENUM('low', 'normal', 'high', 'urgent') DEFAULT 'normal',
    `payment` INT NOT NULL,
    `deadline` TIMESTAMP NULL,
    `assigned_to` VARCHAR(50) NULL,
    `status` ENUM('available', 'assigned', 'in_progress', 'completed', 'expired') DEFAULT 'available',
    `notes` TEXT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL,
    INDEX `idx_status` (`status`),
    INDEX `idx_assigned` (`assigned_to`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Player Charter Requests (players can order flights)
CREATE TABLE IF NOT EXISTS `airline_charter_requests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `client_citizenid` VARCHAR(50) NOT NULL,
    `client_name` VARCHAR(100) NULL,
    `client_phone` VARCHAR(20) NULL,

    -- Request Details
    `pickup_airport` VARCHAR(50) NOT NULL,
    `destination_airport` VARCHAR(50) NOT NULL,
    `passenger_count` INT DEFAULT 1,
    `requested_time` TIMESTAMP NULL,
    `flexibility` ENUM('exact', 'flexible_1hr', 'flexible_day', 'asap') DEFAULT 'flexible_1hr',

    -- Special Requests
    `vip_service` BOOLEAN DEFAULT FALSE,
    `luggage_kg` INT DEFAULT 0,
    `special_requests` TEXT NULL,

    -- Pricing
    `quoted_price` INT NULL,
    `deposit_paid` INT DEFAULT 0,
    `final_price` INT NULL,

    -- Assignment
    `assigned_pilot` VARCHAR(50) NULL,
    `assigned_aircraft` VARCHAR(50) NULL,
    `status` ENUM('pending', 'quoted', 'confirmed', 'assigned', 'in_progress', 'completed', 'cancelled', 'no_show') DEFAULT 'pending',

    -- Completion
    `pickup_time` TIMESTAMP NULL,
    `dropoff_time` TIMESTAMP NULL,
    `pilot_rating` INT NULL,                         -- 1-5 stars
    `client_feedback` TEXT NULL,

    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX `idx_client` (`client_citizenid`),
    INDEX `idx_pilot` (`assigned_pilot`),
    INDEX `idx_status` (`status`)
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
