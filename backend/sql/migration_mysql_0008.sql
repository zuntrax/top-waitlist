-- Backend service should be stopped before applying this migration.

CREATE TABLE `account` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `main_character` BIGINT NOT NULL
) Engine=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `character` ADD COLUMN `account_id` BIGINT NOT NULL;

-- Create accounts for characters not flagged as alts.
INSERT INTO `account` (`main_character`)
SELECT cha.id AS `main_character`
FROM `character` AS cha
LEFT JOIN `alt_character` AS alt ON
    alt.alt_id = cha.id
WHERE alt.alt_id IS NULL;

-- Link characters to accounts.
UPDATE `character`, (
    SELECT
        cha.id AS `character_id`,
        acc.id AS `account_id`
    FROM `character` AS cha
    LEFT JOIN `alt_character` AS alt ON alt.alt_id = cha.id
    LEFT JOIN `account` AS acc ON acc.main_character = COALESCE(alt.account_id, cha.id)
) AS mapping
SET `character`.account_id = mapping.account_id
WHERE `character`.id = mapping.character_id;

-- Get rid of old alt mapping table.
DROP TABLE `alt_character`;

-- Create new account-based role table.
CREATE TABLE `role` (
  `account_id` BIGINT PRIMARY KEY NOT NULL,
  `role` VARCHAR(64) NOT NULL,
  `granted_at` BIGINT NOT NULL,
  `granted_by_id` BIGINT NOT NULL,
  CONSTRAINT `granted_to` FOREIGN KEY (`account_id`) REFERENCES `account` (`id`),
  CONSTRAINT `granted_by` FOREIGN KEY (`granted_by_id`) REFERENCES `account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Copy over roles.
-- This assumes there exists at most one character with roles in each account.
-- I've seen validation code that prevents logging into a character with roles
-- as an alt, so I'm fairly confident that this will not cause issues.
INSERT INTO `role` (`account_id`, `role`, `granted_at`, `granted_by_id`)
SELECT
    cha.account_id AS `account_id`,
    adm.role AS `role`,
    adm.granted_at AS `granted_at`,
    grn.account_id AS `granted_by_id`
FROM `admin` AS adm
INNER JOIN `character` AS cha ON
    cha.id = adm.character_id
INNER JOIN `character` AS grn ON
    grn.id = adm.granted_by_id;

-- Get rid of the old role infrastructure.
DROP TABLE `admin`;
