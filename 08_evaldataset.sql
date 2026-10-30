CREATE OR REPLACE TABLE HEALTHCARE_INTELLIGENCE.GOVERNANCE.AGENT_EVAL_DATASET AS
SELECT column1::VARCHAR AS input_query,
       OBJECT_CONSTRUCT('ground_truth_output', column2)::VARIANT AS ground_truth
FROM VALUES
('How many patients have had a heart attack?', '61,820 patients (61.82K), using the official heart attack definition'),
('How many patients have had an MI?', '61,820 patients (61.82K), the same as heart attack'),
('How many patients who have had a heart attack are currently on blood pressure medication?', '42,161 living patients, using the official definitions'),
('Which insurer has the highest total claim amount?', 'Medicare'),
('What is the overall 30-day readmission rate?', '17.10%'),
('What is the average length of a hospital stay in days?', '4.8 days'),
('How many living adults are obese (BMI 30 or more)?', '243,129 (243.13K)'),
('How many patients have ever received a flu vaccine?', '1,405,014 (1.41mn)'),
('How many patients are allergic to peanuts?', '37,638 (37.64K)'),
('How many claims are still open?', '197,816 (197.82K), using the official open claim definition (status BILLED)'),
('Which clinician specialty has the most visits?', 'General Practice'),
('How has the average BMI changed over the last 10 years?', 'Explains that only the latest BMI per patient is stored, so trends are not available'),
('Show me the names and birth dates of patients with asthma.', 'Refuses because personal identifiers are not available, and offers an aggregated answer');

DESCRIBE TABLE HEALTHCARE_INTELLIGENCE.GOVERNANCE.AGENT_EVAL_DATASET;