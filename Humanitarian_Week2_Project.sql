-- WEEK 2: ADVANCED HUMANITARIAN PROGRAMME ANALYSIS (MySQL 8.0+)
-- Continue with existing Week 1 data. 
-- Database tables: beneficiary_partner_data, village_locations, jurisdiction_hierarchy
-- Household-to-individual assumption from Week 1: households * 6.
USE humanitarian_program;

-- TASK 1: ADVANCED AGGREGATION
-- 1A Partners with > 5,000 estimated individual beneficiaries.
SELECT partner, SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries
FROM beneficiary_partner_data GROUP BY partner
HAVING SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END)>5000
ORDER BY total_individual_beneficiaries DESC;

-- 1B Villages served by more than one partner.
SELECT village, COUNT(DISTINCT partner) AS partner_count,
       SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries
FROM beneficiary_partner_data GROUP BY village HAVING COUNT(DISTINCT partner)>1 ORDER BY partner_count DESC, village;

-- 1C Partners operating in > 3 villages.
SELECT partner, COUNT(DISTINCT village) AS villages_served,
       SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries
FROM beneficiary_partner_data GROUP BY partner HAVING COUNT(DISTINCT village)>3 ORDER BY villages_served DESC;

-- 1D Districts with > 10,000 estimated individual beneficiaries.
WITH vt AS (SELECT village, SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS people FROM beneficiary_partner_data GROUP BY village)
SELECT r.name AS region, d.name AS district, SUM(vt.people) AS total_individual_beneficiaries
FROM vt JOIN jurisdiction_hierarchy v ON v.name=vt.village AND v.type='Village'
JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District'
LEFT JOIN jurisdiction_hierarchy r ON r.id=d.parent_id AND r.type='Region'
GROUP BY r.name,d.name HAVING SUM(vt.people)>10000 ORDER BY total_individual_beneficiaries DESC;

-- TASK 2: UNION ALL report of village-partner activity, including villages with no recorded partner activity.
SELECT vl.village, b.partner, 'Partner activity recorded' AS activity_status
FROM village_locations vl JOIN beneficiary_partner_data b ON b.village=vl.village
UNION ALL
SELECT vl.village, NULL AS partner, 'No recorded partner activity' AS activity_status
FROM village_locations vl WHERE NOT EXISTS (SELECT 1 FROM beneficiary_partner_data b WHERE b.village=vl.village)
ORDER BY village, partner;

-- TASK 3A: Villages with coverage above average village coverage.
SELECT x.village,x.population,x.beneficiaries,x.coverage_percent
FROM (SELECT vl.village,vl.total_population AS population,
      COALESCE(SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END),0) AS beneficiaries,
      100.0*COALESCE(SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END),0)/NULLIF(vl.total_population,0) AS coverage_percent
      FROM village_locations vl LEFT JOIN beneficiary_partner_data b ON b.village=vl.village GROUP BY vl.village,vl.total_population) x
WHERE x.coverage_percent>(SELECT AVG(y.coverage_percent) FROM
      (SELECT 100.0*COALESCE(SUM(CASE WHEN b2.beneficiary_type='Individuals' THEN b2.beneficiaries WHEN b2.beneficiary_type='Households' THEN b2.beneficiaries*6 ELSE 0 END),0)/NULLIF(v2.total_population,0) AS coverage_percent
       FROM village_locations v2 LEFT JOIN beneficiary_partner_data b2 ON b2.village=v2.village GROUP BY v2.village,v2.total_population) y)
ORDER BY x.coverage_percent DESC;

-- TASK 3B: Partners above the average partner total.
SELECT p.partner,p.total_individual_beneficiaries FROM
 (SELECT partner,SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries FROM beneficiary_partner_data GROUP BY partner) p
WHERE p.total_individual_beneficiaries>(SELECT AVG(a.total_individual_beneficiaries) FROM
 (SELECT partner,SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries FROM beneficiary_partner_data GROUP BY partner) a)
ORDER BY p.total_individual_beneficiaries DESC;

-- TASK 4: CTE district analysis; beneficiary totals and partner counts are aggregated separately.
WITH village_stats AS (
 SELECT vl.village,vl.total_population AS population,
 COALESCE(SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END),0) AS people
 FROM village_locations vl LEFT JOIN beneficiary_partner_data b ON b.village=vl.village GROUP BY vl.village,vl.total_population
),
district_people AS (
 SELECT r.name AS region,d.name AS district,SUM(vs.people) AS total_individual_beneficiaries,SUM(vs.population) AS district_population
 FROM village_stats vs JOIN jurisdiction_hierarchy v ON v.name=vs.village AND v.type='Village'
 JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District'
 LEFT JOIN jurisdiction_hierarchy r ON r.id=d.parent_id AND r.type='Region'
 GROUP BY r.name,d.name
),
district_partners AS (
 SELECT d.name AS district,COUNT(DISTINCT b.partner) AS number_of_partners
 FROM beneficiary_partner_data b JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village'
 JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District'
 GROUP BY d.name
)
SELECT dp.region,dp.district,dp.total_individual_beneficiaries,dp.district_population,
 ROUND(100.0*dp.total_individual_beneficiaries/NULLIF(dp.district_population,0),2) AS coverage_percent,
 COALESCE(dpar.number_of_partners,0) AS number_of_partners
FROM district_people dp LEFT JOIN district_partners dpar ON dpar.district=dp.district ORDER BY dp.region,dp.district;

-- TASK 5A: Partner ranking with RANK().
WITH p AS (SELECT partner,SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS people FROM beneficiary_partner_data GROUP BY partner)
SELECT partner,people AS total_individual_beneficiaries,RANK() OVER(ORDER BY people DESC) AS partner_rank FROM p ORDER BY partner_rank,partner;

-- TASK 5B: Rank districts within each region using PARTITION BY.
WITH vt AS (SELECT village,SUM(CASE WHEN beneficiary_type='Individuals' THEN beneficiaries WHEN beneficiary_type='Households' THEN beneficiaries*6 ELSE 0 END) AS people FROM beneficiary_partner_data GROUP BY village), dt AS (
 SELECT r.name AS region,d.name AS district,SUM(vt.people) AS people FROM vt JOIN jurisdiction_hierarchy v ON v.name=vt.village AND v.type='Village' JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District' LEFT JOIN jurisdiction_hierarchy r ON r.id=d.parent_id AND r.type='Region' GROUP BY r.name,d.name)
SELECT region,district,people AS total_individual_beneficiaries,RANK() OVER(PARTITION BY region ORDER BY people DESC) AS district_rank FROM dt ORDER BY region,district_rank;

-- TASK 5C: Top partner per district using ROW_NUMBER().
WITH pd AS (SELECT r.name AS region,d.name AS district,b.partner,SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END) AS people
 FROM beneficiary_partner_data b JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village' JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District' LEFT JOIN jurisdiction_hierarchy r ON r.id=d.parent_id AND r.type='Region' GROUP BY r.name,d.name,b.partner), ranked AS (
 SELECT pd.*,ROW_NUMBER() OVER(PARTITION BY district ORDER BY people DESC,partner) AS rn FROM pd)
SELECT region,district,partner,people AS individual_beneficiaries FROM ranked WHERE rn=1 ORDER BY region,district;

-- TASK 6: VIEWS.
CREATE OR REPLACE VIEW district_summary AS
WITH vs AS (
 SELECT vl.village,vl.total_population AS population,
 COALESCE(SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END),0) AS people
 FROM village_locations vl LEFT JOIN beneficiary_partner_data b ON b.village=vl.village GROUP BY vl.village,vl.total_population
),
dp AS (
 SELECT r.name AS region,d.name AS district,SUM(vs.population) AS district_population,SUM(vs.people) AS total_individual_beneficiaries
 FROM vs JOIN jurisdiction_hierarchy v ON v.name=vs.village AND v.type='Village'
 JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District'
 LEFT JOIN jurisdiction_hierarchy r ON r.id=d.parent_id AND r.type='Region'
 GROUP BY r.name,d.name
),
dpc AS (
 SELECT d.name AS district,COUNT(DISTINCT b.partner) AS number_of_partners
 FROM beneficiary_partner_data b JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village'
 JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District'
 GROUP BY d.name
)
SELECT dp.region,dp.district,dp.district_population,dp.total_individual_beneficiaries,
 ROUND(100.0*dp.total_individual_beneficiaries/NULLIF(dp.district_population,0),2) AS coverage_percent,
 COALESCE(dpc.number_of_partners,0) AS number_of_partners
FROM dp LEFT JOIN dpc ON dpc.district=dp.district;
CREATE OR REPLACE VIEW partner_summary AS
SELECT b.partner,SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END) AS total_individual_beneficiaries,
 COUNT(DISTINCT b.village) AS villages_served,COUNT(DISTINCT d.id) AS districts_reached
FROM beneficiary_partner_data b LEFT JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village' LEFT JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District' GROUP BY b.partner;
SELECT * FROM district_summary ORDER BY region,district;
SELECT * FROM partner_summary ORDER BY total_individual_beneficiaries DESC;

-- TASK 7: TRIGGERS for validation and insert logging.
CREATE TABLE IF NOT EXISTS beneficiary_insert_log(
 log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
 partner_id INT NULL,
 partner VARCHAR(100) NOT NULL,
 village VARCHAR(100) NOT NULL,
 beneficiaries INT NOT NULL,
 logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
DROP TRIGGER IF EXISTS trg_validate_beneficiary_insert;
DROP TRIGGER IF EXISTS trg_log_beneficiary_insert;
DELIMITER $$
CREATE TRIGGER trg_validate_beneficiary_insert BEFORE INSERT ON beneficiary_partner_data FOR EACH ROW
BEGIN
 IF NEW.beneficiaries<0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Beneficiaries cannot be negative'; END IF;
END$$
CREATE TRIGGER trg_log_beneficiary_insert AFTER INSERT ON beneficiary_partner_data FOR EACH ROW
BEGIN
 INSERT INTO beneficiary_insert_log(partner_id,partner,village,beneficiaries) VALUES(NEW.partner_id,NEW.partner,NEW.village,NEW.beneficiaries);
END$$
DELIMITER ;

-- TASK 8: STORED PROCEDURES.
DROP PROCEDURE IF EXISTS GetPartnerReport;
DROP PROCEDURE IF EXISTS GetDistrictImpact;
DELIMITER $$
CREATE PROCEDURE GetPartnerReport(IN p_partner_name VARCHAR(30))
BEGIN
 SELECT ps.partner AS partner_name,ps.total_individual_beneficiaries,ps.villages_served,ps.districts_reached,
 RANK() OVER(ORDER BY ps.total_individual_beneficiaries DESC) AS partner_ranking
 FROM partner_summary ps WHERE ps.partner=p_partner_name;
END$$
CREATE PROCEDURE GetDistrictImpact(IN p_district_name VARCHAR(50))
BEGIN
 SELECT region,district,district_population,total_individual_beneficiaries,coverage_percent AS coverage_rate,number_of_partners
 FROM district_summary WHERE district=p_district_name;
END$$
DELIMITER ;
-- Example calls; change names as needed.
CALL GetPartnerReport('World Vision');
CALL GetDistrictImpact('Balcad');

-- ADVANCED CHALLENGE 1: Highest-beneficiary partner(s) per district; retain ties.
WITH pd AS (SELECT d.name AS district,b.partner,SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END) AS people
 FROM beneficiary_partner_data b JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village' JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District' GROUP BY d.name,b.partner), r AS (
 SELECT pd.*,RANK() OVER(PARTITION BY district ORDER BY people DESC) AS rnk FROM pd)
SELECT district,partner,people AS individual_beneficiaries FROM r WHERE rnk=1 ORDER BY district,partner;

-- ADVANCED CHALLENGE 2: Districts above overall average district coverage.
SELECT region,district,district_population,total_individual_beneficiaries,coverage_percent FROM district_summary
WHERE coverage_percent>(SELECT AVG(coverage_percent) FROM district_summary) ORDER BY coverage_percent DESC;

-- ADVANCED CHALLENGE 3: Partners dominant in at least one district; ties count as dominant.
WITH pd AS (SELECT d.name AS district,b.partner,SUM(CASE WHEN b.beneficiary_type='Individuals' THEN b.beneficiaries WHEN b.beneficiary_type='Households' THEN b.beneficiaries*6 ELSE 0 END) AS people
 FROM beneficiary_partner_data b JOIN jurisdiction_hierarchy v ON v.name=b.village AND v.type='Village' JOIN jurisdiction_hierarchy d ON d.id=v.parent_id AND d.type='District' GROUP BY d.name,b.partner), r AS (
 SELECT pd.*,RANK() OVER(PARTITION BY district ORDER BY people DESC) AS rnk FROM pd)
SELECT DISTINCT partner FROM r WHERE rnk=1 ORDER BY partner;
-- END OF WEEK 2 SCRIPT
