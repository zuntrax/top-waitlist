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

-- Dokuwiki access can now be tied to accounts instead of characters.
ALTER TABLE `wiki_user` ADD COLUMN `account_id` BIGINT NOT NULL;
ALTER TABLE `wiki_user` ADD CONSTRAINT `wiki_account` FOREIGN KEY (`account_id`) REFERENCES `account` (`id`)

UPDATE wiki_user, (
    SELECT
        wik.character_id,
        cha.account_id
    FROM wiki_user AS wik
    JOIN `character` AS cha ON
        cha.id = wik.character_id
) AS mapping
SET wiki_user.account_id = mapping.account_id
WHERE wiki_user.character_id = mapping.character_id;

ALTER VIEW `dokuwiki_user` AS
SELECT
    w.user AS `user`,
    c.name AS `name`,
    w.hash AS `hash`,
    w.mail AS `mail`
FROM `wiki_user` AS w
JOIN `account` AS a ON
    a.id = w.account_id
JOIN `character` AS c ON
    c.id = a.main_character;

ALTER VIEW `dokuwiki_groups` AS
SELECT
    u.user as `user`,
    COALESCE(m.dokuwiki_role, LOWER(r.role)) AS `group`
FROM `wiki_user` as u
JOIN `role` AS r USING (`account_id`)
LEFT JOIN `role_mapping` AS m ON
    m.waitlist_role = r.role;

-- Get rid of the old role infrastructure.
DROP TABLE `admin`;
ALTER TABLE `wiki_user` DROP CONSTRAINT `wiki_character`;
ALTER TABLE `wiki_user` DROP COLUMN `character_id`;
