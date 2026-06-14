

------2-------
SELECT * 
FROM cohort_users_raw 
LIMIT 10; 

------3-------
select *
from cohort_events_raw
limit 10;


------4-------

-- CTE (Common Table Expression) для попередньої обробки даних користувачів
WITH users_parsed AS (
    SELECT
        u.user_id,  -- Унікальний ідентифікатор користувача
        u.signup_datetime,  -- Дата та час реєстрації у сирому форматі
        u.promo_signup_flag,  -- Флаг, чи користувач зареєструвався через промо-акцію
        -- Очищення дати: відділяємо тільки дату від часу, замінюємо різні роздільники на дефіс і прибираємо зайві пробіли
        REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(u.signup_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
    FROM cohort_users_raw u
)

-- Основний запит: конвертація очищеної дати у формат 'DD-MM-YYYY'
SELECT
    user_id,
    promo_signup_flag,
    signup_datetime,
    CASE
        -- Якщо дата вже у форматі 'день-місяць-рік' (4 цифри року)
        WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
            TO_CHAR(TO_DATE(cleaned_date_str, 'DD-MM-YYYY'), 'DD-MM-YYYY')
        -- Якщо дата у форматі з двома цифрами року (наприклад, 25 замість 2025)
        WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN
            TO_CHAR(TO_DATE(cleaned_date_str, 'DD-MM-YY'), 'DD-MM-YYYY')
        ELSE NULL  -- Якщо формат дати не відповідає очікуваному, повертаємо NULL
    END AS signup_date
FROM users_parsed;


------5-------

-- CTE для попередньої обробки подій користувачів
WITH events_parsed AS (
    SELECT
        e.user_id,  -- Унікальний ідентифікатор користувача
        e.event_type,  -- Тип події (наприклад, login, purchase)
        -- Очищення дати події: беремо лише частину з датою, замінюємо '.', '/' на '-', видаляємо пробіли
        REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(e.event_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
    FROM cohort_events_raw e
)

-- Основний запит: конвертація очищеної дати події у стандартний формат
SELECT
    user_id,  -- Ідентифікатор користувача
    event_type,  -- Тип події
    CASE
        -- Якщо дата у форматі день-місяць-рік (4 цифри року)
        WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
            TO_CHAR(TO_DATE(cleaned_date_str, 'DD-MM-YYYY'), 'DD-MM-YYYY')
        -- Якщо дата у форматі день-місяць-рік (2 цифри року)
        WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN
            TO_CHAR(TO_DATE(cleaned_date_str, 'DD-MM-YY'), 'DD-MM-YYYY')
        -- Якщо формат дати не відповідає очікуваному
        ELSE NULL
    END AS event_date  -- Конвертована дата події у форматі DD-MM-YYYY
FROM events_parsed;


------6-------


-- CTE для очищення подій користувачів
WITH events_clean AS (
    SELECT
        user_id,  -- Ідентифікатор користувача
        event_type,  -- Тип події
        -- Конвертація очищеної дати у формат DATE
        CASE
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YYYY')
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YY')
        END AS event_date
    FROM (
        -- Очищення рядка дати події від пробілів та різних роздільників
        SELECT
            user_id,
            event_type,
            REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(event_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
        FROM cohort_events_raw
    ) e
),

-- CTE для очищення даних користувачів
users_clean AS (
    SELECT
        user_id,  -- Ідентифікатор користувача
        promo_signup_flag,  -- Флаг промо-реєстрації
        -- Конвертація очищеної дати реєстрації у формат DATE
        CASE
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YYYY')
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YY')
        END AS signup_date
    FROM (
        -- Очищення рядка дати реєстрації від пробілів та різних роздільників
        SELECT
            user_id,
            promo_signup_flag,
            REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(signup_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
        FROM cohort_users_raw
    ) u
)

-- Основний запит: об’єднання подій та користувачів
SELECT
    u.user_id,  -- Ідентифікатор користувача
    u.promo_signup_flag,  -- Промо-флаг
    e.event_type,  -- Тип події
    u.signup_date,  -- Дата реєстрації
    e.event_date,  -- Дата події
    TO_CHAR(u.signup_date, 'YYYY-MM') AS cohort_month,  -- Місяць когорти у форматі YYYY-MM
    (
        -- Розрахунок місячного зсуву події від дати реєстрації
        EXTRACT(YEAR FROM e.event_date) * 12 + EXTRACT(MONTH FROM e.event_date)
        -
        (EXTRACT(YEAR FROM u.signup_date) * 12 + EXTRACT(MONTH FROM u.signup_date))
    ) AS month_offset
FROM users_clean u
JOIN events_clean e
    ON u.user_id = e.user_id  -- З’єднання подій з користувачами по user_id
WHERE
    u.signup_date IS NOT NULL  -- Відкидаємо користувачів без дати реєстрації
    AND e.event_date IS NOT NULL  -- Відкидаємо події без дати
    AND e.event_type IS NOT NULL  -- Відкидаємо події без типу
    AND e.event_type != 'test_event';  -- Виключаємо тестові події
    
    ---Коротка логіка розрахунків----
 1. Очищення дат: виділяємо дату з datetime, замінюємо різні роздільники на дефіс, конвертуємо у тип DATE.
 2. Об’єднання: зв’язуємо події з користувачами по user_id.
 3. Когорти: формуємо cohort_month як рік-місяць реєстрації.
 4. Місячний зсув (month_offset): рахуємо, скільки місяців пройшло від дати реєстрації до події, використовуючи EXTRACT(YEAR/MONTH) і перетворюючи в місяці.


------7-------

-- CTE для очищення даних користувачів
WITH users_clean AS (
    SELECT
        u.user_id,  -- Ідентифікатор користувача
        u.promo_signup_flag,  -- Флаг промо-реєстрації
        -- Конвертація очищеної дати реєстрації у формат DATE
        CASE
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YYYY')
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YY')
        END AS signup_date
    FROM (
        -- Очищення рядка дати реєстрації від пробілів та різних роздільників
        SELECT
            u.user_id,
            u.promo_signup_flag,
            REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(u.signup_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
        FROM cohort_users_raw u
    ) u
),

-- CTE для очищення даних подій
events_clean AS (
    SELECT
        e.user_id,  -- Ідентифікатор користувача
        e.event_type,  -- Тип події
        -- Конвертація очищеної дати події у формат DATE
        CASE
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YYYY')
            WHEN cleaned_date_str ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN TO_DATE(cleaned_date_str, 'DD-MM-YY')
        END AS event_date
    FROM (
        -- Очищення рядка дати події від пробілів та різних роздільників
        SELECT
            e.user_id,
            e.event_type,
            REPLACE(REPLACE(REPLACE(TRIM(SPLIT_PART(e.event_datetime, ' ', 1)), '.', '-'), '/', '-'), ' ', '') AS cleaned_date_str
        FROM cohort_events_raw e
    ) e
),

-- CTE для об’єднання користувачів та їхніх подій з розрахунком зсуву в місяцях
user_event_activity AS (
    SELECT
        u.user_id,  -- Ідентифікатор користувача
        u.promo_signup_flag,  -- Промо-флаг
        e.event_type,  -- Тип події
        u.signup_date,  -- Дата реєстрації
        e.event_date,  -- Дата події
        TO_CHAR(u.signup_date, 'YYYY-MM') AS cohort_month,  -- Місяць когорти
        -- Розрахунок зсуву події від дати реєстрації у місяцях
        (EXTRACT(YEAR FROM e.event_date) * 12 + EXTRACT(MONTH FROM e.event_date)
         -
         (EXTRACT(YEAR FROM u.signup_date) * 12 + EXTRACT(MONTH FROM u.signup_date))
        ) AS month_offset
    FROM users_clean u
    JOIN events_clean e
        ON u.user_id = e.user_id  -- З’єднання по користувачу
    WHERE 
        u.signup_date IS NOT NULL
        AND e.event_date IS NOT NULL
        AND e.event_type IS NOT NULL
        AND e.event_type != 'test_event'  -- Виключаємо тестові події
        AND e.event_date BETWEEN DATE '2025-01-01' AND DATE '2025-06-30'  -- Фільтр за датою події
)

-- Підсумковий запит: підрахунок унікальних користувачів по когортах і місячному зсуву
SELECT
    promo_signup_flag,  -- Промо-флаг користувачів
    cohort_month,  -- Місяць когорти
    month_offset,  -- Місячний зсув події від дати реєстрації
    COUNT(DISTINCT user_id) AS users_total  -- Кількість унікальних користувачів
FROM user_event_activity
GROUP BY
    promo_signup_flag,
    cohort_month,
    month_offset
ORDER BY
    promo_signup_flag,
    cohort_month,
    month_offset;


   ---Коротка логіка розрахунків----

 1. Очищення дат для користувачів та подій → конвертація у формат DATE.
 2. Об’єднання користувачів і подій по user_id.
 3. Фільтри: виключення NULL-ів, тестових подій і подій поза заданим періодом.
 4. Місячний зсув (month_offset): рахуємо, скільки місяців пройшло від дати реєстрації до події.
 5. Агрегація: підрахунок унікальних користувачів по promo_signup_flag, когортах (cohort_month) і month_offset.