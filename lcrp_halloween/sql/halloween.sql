-- Optional: the resource creates this table automatically on start.
CREATE TABLE IF NOT EXISTS `lcrp_halloween_claims` (
    `identifier` VARCHAR(64) NOT NULL,
    `year` SMALLINT UNSIGNED NOT NULL,
    `day` TINYINT UNSIGNED NOT NULL,
    `status` VARCHAR(10) NOT NULL DEFAULT 'claimed', -- 'pending' = rolled but not collected yet
    `segment` TINYINT UNSIGNED NULL,                  -- wheel segment the spin landed on
    `reward` LONGTEXT NULL,                           -- JSON of the rolled reward
    `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `year`, `day`)
);
