# Play-With-PostgreSQL
# 🐘 CẨM NANG SINH TỒN & ĐÀO TẠO PHỎNG VẤN POSTGRESQL

> **Dành cho Fresher/Junior Backend — Hệ sinh thái Java / Spring Boot**
>
> 🎯 Database xuyên suốt: **Hệ thống Học tập Trực tuyến (E-Learning)**
>
> 📅 Biên soạn: Tháng 9/2026

---

## MỤC LỤC

| Phần | Nội dung | Trang |
|------|----------|-------|
| **Phần 0** | Khởi tạo Phòng Thí Nghiệm (Lab Setup) | [→ Đi tới](#phần-0-khởi-tạo-phòng-thí-nghiệm-lab-setup) |
| **Phần 1** | Thiết kế CSDL & Đặc quyền của Postgres | [→ Đi tới](#phần-1-thiết-kế-csdl--đặc-quyền-của-postgres) |
| **Phần 2** | Kỹ năng Truy vấn Nâng cao (Window Functions & CTE) | [→ Đi tới](#phần-2-kỹ-năng-truy-vấn-nâng-cao-window-functions--cte) |
| **Phần 3** | Tối ưu hóa Hiệu năng & Indexing | [→ Đi tới](#phần-3-tối-ưu-hóa-hiệu-năng--indexing-trong-postgres) |
| **Phần 4** | Concurrency & Bài toán Ghi danh Khóa học | [→ Đi tới](#phần-4-concurrency--bài-toán-ghi-danh-khóa-học) |
| **Phần 5** | Bài Test Phỏng vấn Tổng hợp (Mock Interview) | [→ Đi tới](#phần-5-bài-test-phỏng-vấn-tổng-hợp-mock-interview) |

---

# PHẦN 0: KHỞI TẠO PHÒNG THÍ NGHIỆM (LAB SETUP)

> **Triết lý:** Trước khi nói về lý thuyết, hãy có một sân chơi thực tế để thực nghiệm.
> Mọi query trong cuốn cẩm nang này đều chạy được trên bộ dữ liệu dưới đây.

## 0.1 — Tạo Extension và Schema

```sql
-- ============================================================
-- BƯỚC 0: Kích hoạt extension uuid-ossp (hoặc pgcrypto)
-- PostgreSQL KHÔNG tự sinh UUID nếu không có extension.
-- Đây là điều MySQL dev hay quên khi chuyển sang Postgres.
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Hàm uuid_generate_v4() sẽ sẵn sàng sau lệnh trên.

-- Tùy chọn: Dùng gen_random_uuid() từ pgcrypto (Postgres 13+)
-- CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

> **💡 Ghi chú cho Spring Boot:** Từ Postgres 13+, hàm `gen_random_uuid()` đã built-in mà không cần extension. Nhưng trong production cũ hơn, bạn vẫn cần `uuid-ossp`.

## 0.2 — Tạo Enum Type (Đặc sản Postgres)

```sql
-- ============================================================
-- Postgres hỗ trợ ENUM như một TYPE riêng biệt (MySQL cũng có 
-- ENUM nhưng nó gắn chặt vào cột, không tái sử dụng được).
-- ============================================================
CREATE TYPE user_role AS ENUM ('STUDENT', 'TEACHER', 'ADMIN');
CREATE TYPE enrollment_status AS ENUM ('ACTIVE', 'COMPLETED', 'DROPPED');
CREATE TYPE course_level AS ENUM ('BEGINNER', 'INTERMEDIATE', 'ADVANCED');
```

## 0.3 — Tạo 5 Bảng Chính

### Bảng 1: `users`

```sql
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       VARCHAR(255) NOT NULL UNIQUE,
    full_name   VARCHAR(150) NOT NULL,
    role        user_role    NOT NULL DEFAULT 'STUDENT',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Index trên cột role để filter nhanh theo vai trò
CREATE INDEX idx_users_role ON users(role);

COMMENT ON TABLE users IS 'Bảng người dùng: Student, Teacher, Admin';
COMMENT ON COLUMN users.id IS 'UUID v4 - Khóa chính phân tán an toàn';
```

### Bảng 2: `courses`

```sql
CREATE TABLE courses (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title           VARCHAR(300) NOT NULL,
    description     TEXT,
    teacher_id      UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    price           NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    level           course_level NOT NULL DEFAULT 'BEGINNER',
    max_students    INT NOT NULL DEFAULT 50,
    is_published    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_courses_teacher ON courses(teacher_id);
CREATE INDEX idx_courses_published ON courses(is_published) WHERE is_published = TRUE;
-- ☝️ Partial Index: Chỉ index các khóa học đã publish. MySQL không có.

COMMENT ON TABLE courses IS 'Bảng khóa học - mỗi khóa thuộc về 1 giảng viên';
```

### Bảng 3: `lessons`

```sql
CREATE TABLE lessons (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title       VARCHAR(300) NOT NULL,
    content     TEXT,
    
    -- ★ JSONB: Lưu metadata linh hoạt cho bài giảng
    -- Ví dụ: {"video_url": "...", "duration_minutes": 45, "attachments": [...]}
    metadata    JSONB NOT NULL DEFAULT '{}',
    
    -- ★ ARRAY: Gắn tags cho bài giảng để tìm kiếm
    tags        TEXT[] NOT NULL DEFAULT '{}',
    
    sort_order  INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lessons_course ON lessons(course_id);

COMMENT ON TABLE lessons IS 'Bài giảng - chứa JSONB metadata và ARRAY tags';
COMMENT ON COLUMN lessons.metadata IS 'JSONB: video_url, duration, attachments, ...';
COMMENT ON COLUMN lessons.tags IS 'TEXT[]: Mảng tags phục vụ tìm kiếm và phân loại';
```

### Bảng 4: `enrollments`

```sql
CREATE TABLE enrollments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id       UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    status          enrollment_status NOT NULL DEFAULT 'ACTIVE',
    enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    
    -- Ràng buộc: 1 học viên chỉ đăng ký 1 khóa học 1 lần
    UNIQUE(student_id, course_id)
);

CREATE INDEX idx_enrollments_student ON enrollments(student_id);
CREATE INDEX idx_enrollments_course  ON enrollments(course_id);

COMMENT ON TABLE enrollments IS 'Bảng ghi danh - trung tâm bài toán Concurrency';
```

### Bảng 5: `quiz_results`

```sql
CREATE TABLE quiz_results (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    score       NUMERIC(5, 2) NOT NULL CHECK (score >= 0 AND score <= 100),
    
    -- ★ JSONB: Cấu hình bài thi + câu trả lời chi tiết
    -- Ví dụ: {
    --   "total_questions": 20,
    --   "time_limit_minutes": 30,
    --   "answers": [
    --     {"question_id": 1, "selected": "B", "correct": "B", "is_correct": true},
    --     {"question_id": 2, "selected": "A", "correct": "C", "is_correct": false}
    --   ],
    --   "submitted_from_ip": "192.168.1.100"
    -- }
    quiz_config JSONB NOT NULL DEFAULT '{}',
    
    taken_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_quiz_student ON quiz_results(student_id);
CREATE INDEX idx_quiz_course  ON quiz_results(course_id);

COMMENT ON TABLE quiz_results IS 'Kết quả trắc nghiệm - JSONB lưu chi tiết đáp án';
```

## 0.4 — Chèn Dữ liệu Mẫu

```sql
-- ============================================================
-- INSERT DỮ LIỆU MẪU (10 dòng Users, 4 Courses, nhiều Lessons...)
-- Mỗi UUID được hardcode để dễ tham chiếu trong các ví dụ sau.
-- ============================================================

-- ======== USERS (3 Teachers, 1 Admin, 6 Students) ========
INSERT INTO users (id, email, full_name, role) VALUES
    ('a1111111-1111-1111-1111-111111111111', 'nguyen.van.a@edu.vn',    'Nguyễn Văn An',     'TEACHER'),
    ('a2222222-2222-2222-2222-222222222222', 'tran.thi.b@edu.vn',      'Trần Thị Bình',     'TEACHER'),
    ('a3333333-3333-3333-3333-333333333333', 'le.admin@edu.vn',        'Lê Quản Trị',       'ADMIN'),
    ('b1111111-1111-1111-1111-111111111111', 'pham.student1@gmail.com','Phạm Minh Hoàng',   'STUDENT'),
    ('b2222222-2222-2222-2222-222222222222', 'do.student2@gmail.com',  'Đỗ Thanh Hà',       'STUDENT'),
    ('b3333333-3333-3333-3333-333333333333', 'vo.student3@gmail.com',  'Võ Quốc Cường',     'STUDENT'),
    ('b4444444-4444-4444-4444-444444444444', 'ngo.student4@gmail.com', 'Ngô Thùy Linh',     'STUDENT'),
    ('b5555555-5555-5555-5555-555555555555', 'bui.student5@gmail.com', 'Bùi Đức Anh',       'STUDENT'),
    ('b6666666-6666-6666-6666-666666666666', 'hoang.student6@gmail.com','Hoàng Yến Nhi',    'STUDENT');

-- ======== COURSES (4 khóa học) ========
INSERT INTO courses (id, title, description, teacher_id, price, level, max_students, is_published) VALUES
    ('c1111111-1111-1111-1111-111111111111', 'Spring Boot từ Zero đến Hero',
        'Khóa học Spring Boot toàn diện cho người mới bắt đầu',
        'a1111111-1111-1111-1111-111111111111', 799000, 'BEGINNER', 50, TRUE),
    ('c2222222-2222-2222-2222-222222222222', 'PostgreSQL Mastery',
        'Đào sâu PostgreSQL cho Backend Developer',
        'a1111111-1111-1111-1111-111111111111', 999000, 'ADVANCED', 30, TRUE),
    ('c3333333-3333-3333-3333-333333333333', 'Docker & Kubernetes thực chiến',
        'Triển khai ứng dụng với container orchestration',
        'a2222222-2222-2222-2222-222222222222', 1299000, 'INTERMEDIATE', 40, TRUE),
    ('c4444444-4444-4444-4444-444444444444', 'Microservices Architecture',
        'Thiết kế hệ thống phân tán với Spring Cloud',
        'a2222222-2222-2222-2222-222222222222', 1499000, 'ADVANCED', 25, FALSE);

-- ======== LESSONS (có JSONB metadata + ARRAY tags) ========
INSERT INTO lessons (id, course_id, title, content, metadata, tags, sort_order) VALUES
    -- Lessons cho Spring Boot course
    ('d1111111-1111-1111-1111-111111111111',
     'c1111111-1111-1111-1111-111111111111',
     'Giới thiệu Spring Boot',
     'Nội dung bài giảng...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-01.mp4", "duration_minutes": 45, 
       "attachments": [{"name": "slides.pdf", "size_mb": 2.5}]}',
     ARRAY['spring', 'java', 'beginner'], 1),

    ('d2222222-2222-2222-2222-222222222222',
     'c1111111-1111-1111-1111-111111111111',
     'Dependency Injection Deep Dive',
     'Nội dung bài giảng DI...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-02.mp4", "duration_minutes": 60,
       "attachments": [{"name": "di-examples.zip", "size_mb": 5.0}]}',
     ARRAY['spring', 'DI', 'IoC', 'advanced'], 2),

    ('d3333333-3333-3333-3333-333333333333',
     'c1111111-1111-1111-1111-111111111111',
     'Spring Data JPA & Hibernate',
     'Nội dung JPA...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-03.mp4", "duration_minutes": 75,
       "attachments": []}',
     ARRAY['spring', 'JPA', 'hibernate', 'database'], 3),

    -- Lessons cho PostgreSQL course
    ('d4444444-4444-4444-4444-444444444444',
     'c2222222-2222-2222-2222-222222222222',
     'JSONB & Indexing nâng cao',
     'Nội dung JSONB...',
     '{"video_url": "https://cdn.edu.vn/videos/pg-01.mp4", "duration_minutes": 90,
       "attachments": [{"name": "jsonb-cheatsheet.pdf", "size_mb": 1.2}],
       "requires_lab": true}',
     ARRAY['postgresql', 'jsonb', 'indexing', 'performance'], 1),

    -- Lessons cho Docker course
    ('d5555555-5555-5555-5555-555555555555',
     'c3333333-3333-3333-3333-333333333333',
     'Container Fundamentals',
     'Nội dung Docker cơ bản...',
     '{"video_url": "https://cdn.edu.vn/videos/dk-01.mp4", "duration_minutes": 55,
       "attachments": [], "requires_lab": true}',
     ARRAY['docker', 'container', 'devops'], 1);

-- ======== ENROLLMENTS (ghi danh) ========
INSERT INTO enrollments (student_id, course_id, status, enrolled_at, completed_at) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 'COMPLETED',
     '2026-01-15 08:00:00+07', '2026-04-20 17:00:00+07'),
    ('b1111111-1111-1111-1111-111111111111', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE',
     '2026-05-01 09:00:00+07', NULL),
    ('b2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 'ACTIVE',
     '2026-03-10 10:30:00+07', NULL),
    ('b2222222-2222-2222-2222-222222222222', 'c3333333-3333-3333-3333-333333333333', 'ACTIVE',
     '2026-06-01 14:00:00+07', NULL),
    ('b3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111', 'COMPLETED',
     '2026-02-01 07:45:00+07', '2026-05-15 16:00:00+07'),
    ('b3333333-3333-3333-3333-333333333333', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE',
     '2026-06-15 08:00:00+07', NULL),
    ('b4444444-4444-4444-4444-444444444444', 'c1111111-1111-1111-1111-111111111111', 'DROPPED',
     '2026-01-20 11:00:00+07', NULL),
    ('b5555555-5555-5555-5555-555555555555', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE',
     '2026-07-01 09:30:00+07', NULL),
    ('b6666666-6666-6666-6666-666666666666', 'c3333333-3333-3333-3333-333333333333', 'ACTIVE',
     '2026-08-01 13:00:00+07', NULL);

-- ======== QUIZ RESULTS (kết quả thi) ========
INSERT INTO quiz_results (student_id, course_id, score, quiz_config, taken_at) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 85.50,
     '{
        "total_questions": 20,
        "time_limit_minutes": 30,
        "passing_score": 60,
        "answers": [
            {"question_id": 1, "selected": "B", "correct": "B", "is_correct": true},
            {"question_id": 2, "selected": "A", "correct": "C", "is_correct": false},
            {"question_id": 3, "selected": "D", "correct": "D", "is_correct": true}
        ],
        "submitted_from_ip": "192.168.1.100"
     }', '2026-04-18 15:30:00+07'),

    ('b2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 72.00,
     '{
        "total_questions": 20,
        "time_limit_minutes": 30,
        "passing_score": 60,
        "answers": [
            {"question_id": 1, "selected": "B", "correct": "B", "is_correct": true},
            {"question_id": 2, "selected": "C", "correct": "C", "is_correct": true}
        ],
        "submitted_from_ip": "10.0.0.55"
     }', '2026-06-20 10:00:00+07'),

    ('b3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111', 95.00,
     '{
        "total_questions": 20,
        "time_limit_minutes": 30,
        "passing_score": 60,
        "answers": [
            {"question_id": 1, "selected": "B", "correct": "B", "is_correct": true},
            {"question_id": 2, "selected": "C", "correct": "C", "is_correct": true},
            {"question_id": 3, "selected": "D", "correct": "D", "is_correct": true}
        ],
        "submitted_from_ip": "172.16.0.12"
     }', '2026-05-10 09:00:00+07'),

    ('b1111111-1111-1111-1111-111111111111', 'c2222222-2222-2222-2222-222222222222', 68.00,
     '{
        "total_questions": 25,
        "time_limit_minutes": 45,
        "passing_score": 70,
        "answers": [
            {"question_id": 1, "selected": "A", "correct": "A", "is_correct": true}
        ],
        "submitted_from_ip": "192.168.1.100"
     }', '2026-08-05 14:00:00+07'),

    ('b3333333-3333-3333-3333-333333333333', 'c2222222-2222-2222-2222-222222222222', 88.50,
     '{
        "total_questions": 25,
        "time_limit_minutes": 45,
        "passing_score": 70,
        "answers": [],
        "submitted_from_ip": "172.16.0.12"
     }', '2026-08-20 11:30:00+07'),

    ('b5555555-5555-5555-5555-555555555555', 'c2222222-2222-2222-2222-222222222222', 42.00,
     '{
        "total_questions": 25,
        "time_limit_minutes": 45,
        "passing_score": 70,
        "answers": [],
        "submitted_from_ip": "10.0.0.77"
     }', '2026-09-01 16:00:00+07'),

    ('b2222222-2222-2222-2222-222222222222', 'c3333333-3333-3333-3333-333333333333', 78.00,
     '{
        "total_questions": 15,
        "time_limit_minutes": 25,
        "passing_score": 65,
        "answers": [
            {"question_id": 1, "selected": "C", "correct": "C", "is_correct": true}
        ],
        "submitted_from_ip": "10.0.0.55"
     }', '2026-09-10 10:00:00+07');
```

## 0.5 — Kiểm tra nhanh Lab

```sql
-- Chạy để xác nhận dữ liệu đã sẵn sàng:
SELECT 'users' AS tbl, COUNT(*) FROM users
UNION ALL SELECT 'courses', COUNT(*) FROM courses
UNION ALL SELECT 'lessons', COUNT(*) FROM lessons
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments
UNION ALL SELECT 'quiz_results', COUNT(*) FROM quiz_results;
```

Kết quả kỳ vọng:

| tbl | count |
|-----|-------|
| users | 9 |
| courses | 4 |
| lessons | 5 |
| enrollments | 9 |
| quiz_results | 7 |

> ✅ **Lab đã sẵn sàng.** Từ bây giờ, mọi query đều chạy trên bộ dữ liệu này.

---

# PHẦN 1: THIẾT KẾ CSDL & ĐẶC QUYỀN CỦA POSTGRES

## 1.1 — UUID vs Auto Increment: Tại sao dự án lớn chọn UUID?

### Bảng so sánh tổng quan

| Tiêu chí | `SERIAL` / Auto Increment | `UUID` (v4) |
|-----------|---------------------------|-------------|
| **Kích thước** | 4 bytes (INT) / 8 bytes (BIGINT) | 16 bytes |
| **Đoán được giá trị** | ✅ Dễ đoán (`/api/users/1`, `/api/users/2`) | ❌ Không thể đoán |
| **Distributed-friendly** | ❌ Cần coordinator tránh trùng | ✅ Sinh ở bất kỳ node nào |
| **Index B-Tree performance** | ✅ Sequential insert, ít page split | ⚠️ Random insert, nhiều page split hơn |
| **Merge data từ nhiều DB** | ❌ Xung đột ID | ✅ Không bao giờ xung đột |
| **Bảo mật API** | ❌ Lộ tổng số bản ghi | ✅ Không lộ thông tin |

### Tại sao hệ thống E-Learning nên dùng UUID?

1. **Bảo mật API Endpoint:** Nếu dùng auto increment, URL `/api/courses/47` cho phép kẻ tấn công duyệt toàn bộ khóa học bằng cách tăng ID. Với UUID: `/api/courses/c1111111-1111-1111-1111-111111111111` — không thể đoán.

2. **Kiến trúc Microservices:** Khi tách E-Learning thành `course-service`, `enrollment-service`, `quiz-service`, mỗi service tự sinh UUID mà không cần hỏi DB trung tâm.

3. **Offline-first mobile app:** Học viên làm bài quiz offline → sinh UUID cục bộ → sync lên server sau. Không lo trùng ID.

### Nhược điểm và cách khắc phục

| Nhược điểm | Giải pháp |
|-------------|-----------|
| UUID v4 random → B-Tree index bị fragmentation | Dùng **UUID v7** (time-ordered) — Postgres chưa native nhưng có lib `pg_uuidv7` |
| Kích thước 16 bytes → JOIN chậm hơn INT | Với dataset < 10 triệu rows, sự khác biệt **không đáng kể** |
| Khó debug bằng mắt | Dùng prefix convention: `usr_`, `crs_` trong application layer |

### Mapping UUID với Spring Boot Entity

```java
import jakarta.persistence.*;
import java.util.UUID;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)  // ★ Spring Boot 3.x+
    @Column(name = "id", updatable = false, nullable = false)
    private UUID id;

    @Column(name = "email", unique = true, nullable = false, length = 255)
    private String email;

    @Column(name = "full_name", nullable = false, length = 150)
    private String fullName;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false)
    private UserRole role;

    // ... getters, setters, constructors
}

// Enum phải map chính xác với Postgres ENUM type
public enum UserRole {
    STUDENT, TEACHER, ADMIN
}
```

> **⚠️ Lưu ý quan trọng về Hibernate + Postgres ENUM:**
> Mặc định, Hibernate gửi giá trị ENUM dưới dạng `VARCHAR`. Postgres sẽ báo lỗi:
> `column "role" is of type user_role but expression is of type character varying`
>
> **Cách fix:** Thêm vào `application.yml`:

```yaml
spring:
  jpa:
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
  datasource:
    url: jdbc:postgresql://localhost:5432/elearning
    driver-class-name: org.postgresql.Driver
```

Hoặc dùng custom `@Type` annotation với Hibernate 6:

```java
import org.hibernate.annotations.JdbcType;
import org.hibernate.dialect.PostgreSQLEnumJdbcType;

@Enumerated(EnumType.STRING)
@JdbcType(PostgreSQLEnumJdbcType.class)  // ★ Hibernate 6.5+
@Column(name = "role", nullable = false)
private UserRole role;
```

---

## 1.2 — JSONB: NoSQL bên trong RDBMS

### JSONB là gì? Tại sao không phải JSON?

| Tiêu chí | `JSON` | `JSONB` |
|-----------|--------|---------|
| **Lưu trữ** | Lưu nguyên text gốc | Lưu dạng binary đã parse |
| **Tốc độ ghi** | Nhanh hơn (không cần parse) | Chậm hơn một chút |
| **Tốc độ đọc/truy vấn** | Chậm (phải parse mỗi lần đọc) | ★ Nhanh vượt trội |
| **Đánh Index** | ❌ Không thể | ✅ GIN Index, GiST |
| **Giữ thứ tự key** | ✅ Có | ❌ Không (đã binary hóa) |
| **Loại bỏ key trùng** | ❌ Giữ nguyên | ✅ Tự động loại bỏ |

> **Quy tắc vàng:** Trong 99% trường hợp, hãy dùng `JSONB`. Chỉ dùng `JSON` khi bạn cần giữ nguyên format gốc (log audit chẳng hạn).

### Khi nào dùng JSONB thay vì tách bảng con?

Trong hệ thống E-Learning, cột `quiz_config` trong bảng `quiz_results` là ví dụ hoàn hảo:

```
★ DÙNG JSONB khi:
├── Cấu trúc dữ liệu thay đổi linh hoạt (mỗi quiz có config khác nhau)
├── Không cần JOIN trên dữ liệu đó thường xuyên
├── Dữ liệu thuộc dạng "metadata" đi kèm entity chính
└── Bạn muốn tránh schema migration mỗi khi thêm field mới

★ TÁCH BẢNG CON khi:
├── Cần tham chiếu quan hệ (Foreign Key) từ bảng khác
├── Cần aggregate (SUM, AVG, COUNT) trên các field con
├── Dữ liệu có quan hệ many-to-many phức tạp
└── Cần ràng buộc UNIQUE/CHECK trên từng field con
```

**Ví dụ thực tế:** Mỗi bài quiz có thể có 15, 20, hoặc 50 câu hỏi. Mỗi câu có `selected`, `correct`, `is_correct`. Nếu tách thành bảng `quiz_answers`, bạn cần:
- 1 bảng `quiz_answers` với hàng triệu rows
- JOIN mỗi khi hiển thị kết quả
- Migration mỗi khi thêm field (ví dụ: `time_spent_seconds` cho từng câu)

Với JSONB, tất cả nằm gọn trong 1 cột, truy vấn linh hoạt bằng operator `->`, `->>`, `@>`.

### Mapping JSONB với Spring Boot

```java
// ★ Cách 1: Dùng String + JsonNode (linh hoạt nhất)
@Entity
@Table(name = "quiz_results")
public class QuizResult {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "student_id", nullable = false)
    private User student;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "course_id", nullable = false)
    private Course course;

    @Column(name = "score", nullable = false)
    private BigDecimal score;

    // ★ JSONB mapping với Hibernate 6+ (dùng JdbcTypeCode)
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "quiz_config", columnDefinition = "jsonb")
    private Map<String, Object> quizConfig;

    @Column(name = "taken_at", nullable = false)
    private OffsetDateTime takenAt;
}
```

```java
// ★ Cách 2: Map JSONB thành POJO (type-safe hơn)
public class QuizConfig {
    private int totalQuestions;
    private int timeLimitMinutes;
    private double passingScore;
    private List<Answer> answers;
    private String submittedFromIp;
    // getters, setters...
    
    public static class Answer {
        private int questionId;
        private String selected;
        private String correct;
        private boolean isCorrect;
        // getters, setters...
    }
}

// Trong Entity:
@JdbcTypeCode(SqlTypes.JSON)
@Column(name = "quiz_config", columnDefinition = "jsonb")
private QuizConfig quizConfig;  // ★ Hibernate tự serialize/deserialize
```

> **💡 So sánh với MySQL:** MySQL 5.7+ có kiểu JSON nhưng **không hỗ trợ đánh GIN Index trên toàn bộ document**. MySQL chỉ hỗ trợ generated column + index. Postgres cho phép `CREATE INDEX idx ON table USING gin(jsonb_column)` trực tiếp — đơn giản và mạnh mẽ hơn rất nhiều.

---

## 1.3 — ARRAY Type: Đặc sản mà MySQL không có

MySQL **không hỗ trợ** kiểu mảng. Muốn lưu tags, bạn phải tạo bảng `lesson_tags` → JOIN mỗi khi query. Postgres giải quyết gọn gàng:

```sql
-- Thêm tag mới vào bài giảng
UPDATE lessons
SET tags = array_append(tags, 'new-tag')
WHERE id = 'd1111111-1111-1111-1111-111111111111';

-- Tìm bài giảng có tag 'spring'
SELECT title, tags
FROM lessons
WHERE 'spring' = ANY(tags);

-- Tìm bài giảng có ĐỒNG THỜI tag 'spring' VÀ 'JPA'
SELECT title, tags
FROM lessons
WHERE tags @> ARRAY['spring', 'JPA'];

-- Đếm số lượng tags
SELECT title, array_length(tags, 1) AS tag_count
FROM lessons;
```

### Mapping ARRAY với Spring Boot (JPA)

```java
@Entity
@Table(name = "lessons")
public class Lesson {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "course_id", nullable = false)
    private Course course;

    @Column(name = "title", nullable = false)
    private String title;

    // ★ Mapping PostgreSQL TEXT[] → Java List<String>
    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "tags", columnDefinition = "text[]")
    private List<String> tags;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "metadata", columnDefinition = "jsonb")
    private Map<String, Object> metadata;
}
```

```java
// Query với Native Query (tận dụng operator Postgres)
@Repository
public interface LessonRepository extends JpaRepository<Lesson, UUID> {

    // Tìm lessons có chứa tag cụ thể
    @Query(value = "SELECT * FROM lessons WHERE :tag = ANY(tags)", nativeQuery = true)
    List<Lesson> findByTag(@Param("tag") String tag);

    // Tìm lessons có chứa TẤT CẢ tags
    @Query(value = "SELECT * FROM lessons WHERE tags @> CAST(:tags AS text[])", 
           nativeQuery = true)
    List<Lesson> findByAllTags(@Param("tags") String[] tags);
}
```

---

## 🎯 GÓC PHỎNG VẤN — PHẦN 1

### ❓ Câu 1: "Tại sao anh/chị chọn UUID thay vì Auto Increment cho hệ thống E-Learning? Có nhược điểm gì không?"

> **💬 Câu trả lời sắc sảo:**
>
> "Em chọn UUID vì 3 lý do chính:
>
> **Thứ nhất, bảo mật API.** Nếu dùng auto increment, endpoint `/api/courses/47` cho phép kẻ tấn công enumrate toàn bộ khóa học bằng cách tăng ID tuần tự — đây là lỗ hổng IDOR (Insecure Direct Object Reference) nằm trong OWASP Top 10.
>
> **Thứ hai, sẵn sàng cho Microservices.** UUID có thể sinh tại application layer (Java `UUID.randomUUID()`) mà không cần round-trip tới database. Khi tách hệ thống thành `course-service` và `enrollment-service`, mỗi service tự sinh ID mà không lo xung đột.
>
> **Thứ ba, hỗ trợ offline-first.** Học viên làm quiz offline trên mobile, UUID được sinh tại client, sync lên server sau mà không bao giờ trùng.
>
> **Về nhược điểm:** UUID v4 là random, gây fragmentation trên B-Tree index, tăng tỷ lệ page split. Giải pháp: sử dụng **UUID v7** (time-ordered, RFC 9562) — giữ tính unique nhưng có prefix thời gian nên insert tuần tự vào index. Từ Postgres 17, có thể dùng `uuidv7()` hoặc library `pg_uuidv7`. Ngoài ra, kích thước 16 bytes so với 4 bytes INT, nhưng với dataset dưới 10 triệu rows, impact trên JOIN performance là không đáng kể."

---

### ❓ Câu 2: "Khi nào anh/chị dùng JSONB thay vì tách bảng con? Cho ví dụ cụ thể từ dự án."

> **💬 Câu trả lời sắc sảo:**
>
> "Em áp dụng nguyên tắc **'Query pattern quyết định schema design'**.
>
> Trong hệ thống E-Learning, em dùng JSONB cho cột `quiz_config` trong bảng `quiz_results` để lưu cấu hình bài thi và chi tiết đáp án. Lý do:
>
> 1. **Schema linh hoạt:** Mỗi bài quiz có cấu hình khác nhau — quiz A có 20 câu/30 phút, quiz B có 50 câu/60 phút, quiz C thêm field `allow_review: true`. Nếu tách bảng, em phải ALTER TABLE mỗi khi thêm field mới.
>
> 2. **Read-heavy, write-once:** Kết quả quiz chỉ ghi 1 lần khi nộp bài, sau đó chỉ đọc. Pattern này phù hợp với JSONB vì overhead khi ghi (phải parse thành binary) chỉ xảy ra 1 lần.
>
> 3. **Không cần JOIN:** Em không bao giờ cần query 'Tìm tất cả quiz mà câu hỏi số 5 được chọn đáp án B' — nếu cần query pattern đó thường xuyên, em sẽ tách bảng.
>
> **Ngược lại, em KHÔNG dùng JSONB cho quan hệ `enrollment`** vì cần Foreign Key constraint, cần COUNT enrolled students, cần JOIN thường xuyên với bảng `courses` và `users`. Đây là relational data thuần túy."

---

### ❓ Câu 3: "PostgreSQL ENUM khác gì MySQL ENUM? Anh/chị map nó với Spring Boot/Hibernate như thế nào?"

> **💬 Câu trả lời sắc sảo:**
>
> "Có 3 điểm khác biệt quan trọng:
>
> | | PostgreSQL ENUM | MySQL ENUM |
> |---|---|---|
> | Định nghĩa | `CREATE TYPE` — là **type riêng biệt**, tái sử dụng được | Gắn vào cột, không tái sử dụng |
> | Thêm giá trị | `ALTER TYPE ... ADD VALUE` — không lock table | Phải `ALTER TABLE` — lock table |
> | Thay đổi thứ tự | Có thể `ADD VALUE ... BEFORE/AFTER` | Phải rebuild column |
>
> Ví dụ: Type `user_role` em dùng cho cả bảng `users` và có thể dùng lại cho bảng `audit_logs` sau này.
>
> **Về mapping với Hibernate 6+:** Mặc định, Hibernate gửi enum dưới dạng `VARCHAR` nhưng Postgres kỳ vọng type `user_role`. Để fix, em dùng `@JdbcType(PostgreSQLEnumJdbcType.class)` từ Hibernate 6.5+. Với các phiên bản cũ hơn, em phải viết custom `UserType` hoặc dùng `@Type(PostgreSQLEnumType.class)` từ thư viện `hibernate-types` của Vlad Mihalcea.
>
> **Lưu ý production:** Postgres ENUM không cho phép xóa hoặc rename giá trị. Nếu cần linh hoạt hơn (ví dụ: thêm role `MODERATOR` rồi sau đó xóa), em sẽ dùng bảng `roles` riêng thay vì ENUM."

---

# PHẦN 2: KỸ NĂNG TRUY VẤN NÂNG CAO (WINDOW FUNCTIONS & CTE)

## 2.1 — Common Table Expressions (CTE) với mệnh đề `WITH`

### Tại sao CTE tốt hơn Subquery?

| Tiêu chí | Subquery lồng nhau | CTE (`WITH`) |
|-----------|---------------------|--------------|
| Đọc hiểu | ❌ Đọc từ trong ra ngoài | ✅ Đọc từ trên xuống dưới |
| Tái sử dụng | ❌ Phải copy-paste | ✅ Đặt tên 1 lần, dùng nhiều lần |
| Debug | ❌ Khó tách riêng để test | ✅ Chạy từng CTE riêng lẻ |
| Đệ quy | ❌ Không hỗ trợ | ✅ `WITH RECURSIVE` |

> **💡 Ghi chú:** MySQL 8.0+ đã hỗ trợ CTE, nhưng Postgres đã có từ version 8.4 (2009) và hỗ trợ **Materialized CTE** (`WITH ... AS MATERIALIZED`) — cho phép kiểm soát query planner tốt hơn.

### Bài toán: Tính doanh thu từng khóa học

**Yêu cầu:** Tính tổng doanh thu (= số học viên ACTIVE/COMPLETED × giá khóa học), sắp xếp theo doanh thu giảm dần. Chỉ tính các khóa học đã publish.

#### ❌ Cách viết Subquery (rườm rà, khó đọc)

```sql
SELECT 
    c.title,
    c.price,
    (SELECT COUNT(*) FROM enrollments e 
     WHERE e.course_id = c.id AND e.status IN ('ACTIVE', 'COMPLETED')) AS total_students,
    c.price * (SELECT COUNT(*) FROM enrollments e 
               WHERE e.course_id = c.id AND e.status IN ('ACTIVE', 'COMPLETED')) AS revenue
FROM courses c
WHERE c.is_published = TRUE
ORDER BY revenue DESC;
```

#### ✅ Cách viết CTE (sạch sẽ, chuyên nghiệp)

```sql
WITH enrollment_stats AS (
    -- Bước 1: Đếm số học viên hợp lệ cho mỗi khóa học
    SELECT 
        course_id,
        COUNT(*) AS total_students
    FROM enrollments
    WHERE status IN ('ACTIVE', 'COMPLETED')
    GROUP BY course_id
),
course_revenue AS (
    -- Bước 2: Kết hợp với thông tin khóa học để tính doanh thu
    SELECT 
        c.id,
        c.title,
        c.price,
        c.level,
        COALESCE(es.total_students, 0) AS total_students,
        c.price * COALESCE(es.total_students, 0) AS revenue
    FROM courses c
    LEFT JOIN enrollment_stats es ON c.id = es.course_id
    WHERE c.is_published = TRUE
)
-- Bước 3: Hiển thị kết quả, bổ sung xếp hạng
SELECT 
    title,
    level,
    price,
    total_students,
    revenue,
    ROUND(revenue / NULLIF(SUM(revenue) OVER (), 0) * 100, 2) AS revenue_pct
FROM course_revenue
ORDER BY revenue DESC;
```

**Kết quả:**

| title | level | price | total_students | revenue | revenue_pct |
|-------|-------|-------|----------------|---------|-------------|
| Spring Boot từ Zero đến Hero | BEGINNER | 799000 | 3 | 2397000 | 35.08 |
| Docker & Kubernetes thực chiến | INTERMEDIATE | 1299000 | 2 | 2598000 | 38.02 |
| PostgreSQL Mastery | ADVANCED | 999000 | 3 | 2997000 | 43.86 |

> **💡 Để ý:** `COALESCE(es.total_students, 0)` xử lý trường hợp khóa học chưa có ai đăng ký (LEFT JOIN trả NULL). Đây là kỹ thuật production-ready.

---

## 2.2 — Window Functions: Vũ khí hạng nặng trong phỏng vấn

### Bài toán kinh điển: "Top 3 học viên điểm cao nhất TRONG MỖI khóa học"

Đây là dạng câu hỏi **xuất hiện trong 80% buổi phỏng vấn SQL** ở mọi cấp độ. Nếu bạn dùng subquery lồng nhau, interviewer sẽ hỏi: *"Có cách nào tốt hơn không?"*

#### ★ Giải pháp Window Function

```sql
WITH ranked_students AS (
    SELECT 
        qr.student_id,
        u.full_name,
        c.title AS course_title,
        qr.score,
        -- ★ RANK(): Cùng điểm → cùng hạng, bỏ qua hạng tiếp theo
        -- ★ DENSE_RANK(): Cùng điểm → cùng hạng, KHÔNG bỏ qua
        -- ★ ROW_NUMBER(): Luôn tăng tuần tự, không quan tâm trùng
        RANK() OVER (
            PARTITION BY qr.course_id    -- ← Chia nhóm theo khóa học
            ORDER BY qr.score DESC       -- ← Sắp xếp điểm giảm dần trong nhóm
        ) AS rank_in_course
    FROM quiz_results qr
    JOIN users u ON qr.student_id = u.id
    JOIN courses c ON qr.course_id = c.id
)
SELECT 
    course_title,
    full_name,
    score,
    rank_in_course
FROM ranked_students
WHERE rank_in_course <= 3  -- ★ Chỉ lấy top 3
ORDER BY course_title, rank_in_course;
```

**Kết quả:**

| course_title | full_name | score | rank_in_course |
|--------------|-----------|-------|----------------|
| Docker & Kubernetes thực chiến | Đỗ Thanh Hà | 78.00 | 1 |
| PostgreSQL Mastery | Trần Thị Bình... (xem chi tiết) | 88.50 | 1 |
| PostgreSQL Mastery | Phạm Minh Hoàng | 68.00 | 2 |
| PostgreSQL Mastery | Bùi Đức Anh | 42.00 | 3 |
| Spring Boot từ Zero đến Hero | Võ Quốc Cường | 95.00 | 1 |
| Spring Boot từ Zero đến Hero | Phạm Minh Hoàng | 85.50 | 2 |
| Spring Boot từ Zero đến Hero | Đỗ Thanh Hà | 72.00 | 3 |

### Phân biệt RANK vs DENSE_RANK vs ROW_NUMBER

```
Giả sử điểm: 95, 95, 85, 72

RANK():        1, 1, 3, 4    ← Bỏ qua hạng 2 (vì có 2 người hạng 1)
DENSE_RANK():  1, 1, 2, 3    ← Không bỏ qua (hạng liên tục)
ROW_NUMBER():  1, 2, 3, 4    ← Luôn duy nhất (random cho 2 người cùng điểm)
```

> **🎯 Mẹo phỏng vấn:** Nếu đề bài nói "Top 3 học viên" → dùng `DENSE_RANK()` nếu muốn lấy đủ, dùng `RANK()` nếu muốn strict. Nếu đề bài nói "3 bản ghi" → dùng `ROW_NUMBER()`.

### Thêm ví dụ: Tính điểm trung bình tích lũy (Running Average)

```sql
-- Tính điểm trung bình tích lũy theo thời gian cho mỗi học viên
SELECT 
    u.full_name,
    c.title,
    qr.score,
    qr.taken_at,
    -- Điểm trung bình tính đến thời điểm hiện tại (running average)
    ROUND(AVG(qr.score) OVER (
        PARTITION BY qr.student_id 
        ORDER BY qr.taken_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS cumulative_avg
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
JOIN courses c ON qr.course_id = c.id
ORDER BY u.full_name, qr.taken_at;
```

---

## 2.3 — Kỹ thuật thao tác với JSONB

### Các operator JSONB quan trọng

| Operator | Ý nghĩa | Kiểu trả về |
|----------|----------|-------------|
| `->` | Truy cập key, trả về JSON | `jsonb` |
| `->>` | Truy cập key, trả về text | `text` |
| `#>` | Truy cập path sâu, trả về JSON | `jsonb` |
| `#>>` | Truy cập path sâu, trả về text | `text` |
| `@>` | Contains (bên trái chứa bên phải?) | `boolean` |
| `?` | Key có tồn tại không? | `boolean` |
| `?\|` | Có BẤT KỲ key nào tồn tại không? | `boolean` |
| `?&` | TẤT CẢ keys đều tồn tại? | `boolean` |
| `\|\|` | Merge 2 JSONB objects | `jsonb` |
| `-` | Xóa key | `jsonb` |

### Bài toán: Trích xuất dữ liệu sâu trong JSONB

```sql
-- ★ Query 1: Lấy time_limit_minutes từ quiz_config
SELECT 
    u.full_name,
    qr.score,
    qr.quiz_config ->> 'time_limit_minutes' AS time_limit,
    qr.quiz_config ->> 'passing_score' AS passing_score,
    -- So sánh score với passing_score
    CASE 
        WHEN qr.score >= (qr.quiz_config ->> 'passing_score')::NUMERIC 
        THEN '✅ PASSED'
        ELSE '❌ FAILED'
    END AS result
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id;
```

```sql
-- ★ Query 2: Truy cập DEEP path — lấy đáp án câu hỏi đầu tiên
-- quiz_config -> 'answers' -> 0 -> 'selected'
SELECT 
    u.full_name,
    qr.quiz_config #>> '{answers, 0, selected}' AS first_answer_selected,
    qr.quiz_config #>> '{answers, 0, correct}' AS first_answer_correct,
    qr.quiz_config #>> '{answers, 0, is_correct}' AS first_answer_result
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
WHERE jsonb_array_length(qr.quiz_config -> 'answers') > 0;
-- ☝️ Chỉ lấy các quiz có ít nhất 1 answer được lưu
```

```sql
-- ★ Query 3: Đếm số câu trả lời đúng từ JSONB array
SELECT 
    u.full_name,
    c.title AS course,
    qr.score,
    qr.quiz_config ->> 'total_questions' AS total_questions,
    -- Dùng jsonb_array_elements để "bung" mảng answers ra
    (SELECT COUNT(*) 
     FROM jsonb_array_elements(qr.quiz_config -> 'answers') AS ans
     WHERE (ans ->> 'is_correct')::BOOLEAN = TRUE
    ) AS correct_count
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
JOIN courses c ON qr.course_id = c.id;
```

```sql
-- ★ Query 4: Tìm tất cả quiz được nộp từ mạng nội bộ (192.168.x.x)
SELECT 
    u.full_name,
    qr.score,
    qr.quiz_config ->> 'submitted_from_ip' AS ip_address
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
WHERE qr.quiz_config ->> 'submitted_from_ip' LIKE '192.168.%';
```

```sql
-- ★ Query 5: UPDATE - Thêm field mới vào JSONB (không cần ALTER TABLE!)
UPDATE quiz_results
SET quiz_config = quiz_config || '{"allow_review": true, "version": 2}'::jsonb
WHERE course_id = 'c1111111-1111-1111-1111-111111111111';
-- ☝️ Operator || merge 2 JSONB objects. MySQL JSON phải dùng JSON_SET().
```

### Thao tác JSONB trong Spring Data JPA (Native Query)

```java
@Repository
public interface QuizResultRepository extends JpaRepository<QuizResult, UUID> {

    // Tìm quiz results theo passing_score threshold
    @Query(value = """
        SELECT qr.* FROM quiz_results qr
        WHERE (qr.quiz_config ->> 'passing_score')::NUMERIC <= :threshold
        """, nativeQuery = true)
    List<QuizResult> findByPassingScoreThreshold(@Param("threshold") double threshold);

    // Tìm quiz nộp từ IP cụ thể
    @Query(value = """
        SELECT qr.* FROM quiz_results qr
        WHERE qr.quiz_config ->> 'submitted_from_ip' = :ip
        """, nativeQuery = true)
    List<QuizResult> findBySubmittedIp(@Param("ip") String ip);

    // Tìm quiz có chứa key 'allow_review' trong config
    @Query(value = """
        SELECT qr.* FROM quiz_results qr
        WHERE qr.quiz_config ? 'allow_review'
        """, nativeQuery = true)
    List<QuizResult> findWithReviewEnabled();
}
```

> **⚠️ Lưu ý:** Ký tự `?` trong native query có thể xung đột với JDBC parameter placeholder. Giải pháp: escape bằng `??` hoặc dùng `jsonb_exists(quiz_config, 'allow_review')`.

---

## 🎯 GÓC PHỎNG VẤN — PHẦN 2

### ❓ Câu 1: "Giải thích sự khác nhau giữa RANK(), DENSE_RANK(), và ROW_NUMBER(). Cho ví dụ khi nào dùng cái nào."

> **💬 Câu trả lời sắc sảo:**
>
> "Cả 3 đều là Window Functions dùng để xếp hạng, nhưng khác nhau khi có giá trị trùng:
>
> Giả sử 4 học viên có điểm: **95, 95, 85, 72**
>
> - `ROW_NUMBER()`: Luôn trả về **1, 2, 3, 4** — mỗi row một số, không bao giờ trùng. Phù hợp khi cần phân trang hoặc chỉ cần 'đúng N bản ghi'.
>
> - `RANK()`: Trả về **1, 1, 3, 4** — hai người cùng 95 điểm đều hạng 1, nhưng hạng 2 bị bỏ qua. Phù hợp cho bảng xếp hạng thi đấu (thể thao, thi Olympic).
>
> - `DENSE_RANK()`: Trả về **1, 1, 2, 3** — hai người cùng 95 điểm đều hạng 1, hạng tiếp theo vẫn là 2. Phù hợp khi cần 'Top N hạng' (ví dụ: tìm 3 mức lương cao nhất, cho dù có nhiều người cùng mức).
>
> **Trong hệ thống E-Learning:** Khi cần 'Top 3 học viên xuất sắc nhất mỗi khóa', em dùng `DENSE_RANK()` vì nếu có 2 người cùng hạng 1, em vẫn muốn lấy người hạng 2 và hạng 3."

---

### ❓ Câu 2: "CTE có phải lúc nào cũng tốt hơn Subquery không? Khi nào CTE có thể gây hại performance?"

> **💬 Câu trả lời sắc sảo:**
>
> "Không phải lúc nào cũng tốt hơn. CTE có 2 dạng:
>
> **1. Inline CTE** (mặc định từ Postgres 12+): Query planner có thể 'flatten' CTE thành subquery và tối ưu cùng với query chính. Trường hợp này, CTE chỉ tốt hơn về **readability**, không khác performance.
>
> **2. Materialized CTE** (`WITH cte AS MATERIALIZED (...)`): Postgres thực thi CTE trước, lưu kết quả vào bộ nhớ tạm, rồi mới chạy query chính. Trường hợp này:
>
> - ✅ **Tốt** khi CTE được tham chiếu **nhiều lần** trong query chính — tránh tính toán lặp.
> - ❌ **Xấu** khi CTE trả về **tập kết quả lớn** nhưng query chính chỉ cần vài rows (vì planner không thể push filter xuống CTE).
>
> **Trước Postgres 12**, mọi CTE đều mặc định Materialized — đây là lý do nhiều bài blog cũ nói 'CTE chậm hơn subquery'. Từ Postgres 12+, điều này không còn đúng nữa.
>
> **Ví dụ cụ thể trong E-Learning:** CTE tính `enrollment_stats` chỉ tham chiếu 1 lần → Postgres tự inline. Nhưng nếu em cần dùng `enrollment_stats` ở cả phần `SELECT` và phần `WHERE` → em có thể force `MATERIALIZED` để tránh tính 2 lần."

---

### ❓ Câu 3: "Viết query lấy tất cả bài giảng có JSONB metadata chứa key 'requires_lab' = true. Giải thích các operator JSONB mà anh/chị dùng."

> **💬 Câu trả lời sắc sảo:**
>
> ```sql
> -- Cách 1: Dùng containment operator @>
> SELECT title, metadata
> FROM lessons
> WHERE metadata @> '{"requires_lab": true}'::jsonb;
> 
> -- Cách 2: Dùng ->> rồi cast
> SELECT title, metadata
> FROM lessons
> WHERE (metadata ->> 'requires_lab')::BOOLEAN = TRUE;
> ```
>
> "Em ưu tiên Cách 1 (`@>` containment) vì:
>
> 1. **GIN Index tương thích:** Nếu cột `metadata` có GIN index, operator `@>` sẽ sử dụng index đó. Còn `->>`  sẽ không dùng GIN mà cần **Expression Index** riêng.
>
> 2. **Ngắn gọn và type-safe:** Không cần cast `::BOOLEAN`, Postgres so sánh trực tiếp JSONB value.
>
> 3. **Linh hoạt:** `@>` có thể kiểm tra nested path phức tạp: `metadata @> '{"attachments": [{"name": "slides.pdf"}]}'` — tìm bài giảng có attachment tên 'slides.pdf'."

---

# PHẦN 3: TỐI ƯU HÓA HIỆU NĂNG & INDEXING TRONG POSTGRES

## 3.1 — EXPLAIN vs EXPLAIN ANALYZE: Đọc vị query của bạn

### EXPLAIN — Xem "Kế hoạch Dự kiến"

```sql
EXPLAIN 
SELECT u.full_name, c.title, qr.score
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
JOIN courses c ON qr.course_id = c.id
WHERE qr.score >= 80;
```

**Output (ví dụ):**
```
Hash Join  (cost=33.50..54.12 rows=3 width=554)
  Hash Cond: (qr.course_id = c.id)
  ->  Hash Join  (cost=16.75..37.25 rows=3 width=308)
        Hash Cond: (qr.student_id = u.id)
        ->  Seq Scan on quiz_results qr  (cost=0.00..20.38 rows=3 width=84)
              Filter: (score >= 80)
        ->  Hash  (cost=12.50..12.50 rows=340 width=240)
              ->  Seq Scan on users u  (cost=0.00..12.50 rows=340 width=240)
  ->  Hash  (cost=12.50..12.50 rows=340 width=262)
        ->  Seq Scan on courses c  (cost=0.00..12.50 rows=340 width=262)
```

> **Cách đọc:** Mỗi node hiển thị `cost=startup_cost..total_cost`, `rows` (ước lượng số dòng), `width` (bytes mỗi dòng). Đây là **ước lượng** của query planner, KHÔNG chạy thực tế.

### EXPLAIN ANALYZE — Xem "Thực tế Chạy"

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT u.full_name, c.title, qr.score
FROM quiz_results qr
JOIN users u ON qr.student_id = u.id
JOIN courses c ON qr.course_id = c.id
WHERE qr.score >= 80;
```

**Output bổ sung:**
```
Hash Join  (cost=33.50..54.12 rows=3 width=554) (actual time=0.085..0.092 rows=3 loops=1)
  ...
  Buffers: shared hit=9
Planning Time: 0.215 ms
Execution Time: 0.128 ms
```

> **Sự khác biệt mấu chốt:** `EXPLAIN` chỉ hiện kế hoạch. `EXPLAIN ANALYZE` **thực sự chạy** query.

### ⚠️ Tại sao EXPLAIN ANALYZE NGUY HIỂM trên Production?

```sql
-- ĐÂY LÀ CÂU HỎI PHỎNG VẤN KINH ĐIỂN!
-- EXPLAIN ANALYZE sẽ THỰC SỰ XÓA DỮ LIỆU:
EXPLAIN ANALYZE DELETE FROM enrollments WHERE status = 'DROPPED';
-- ☝️ Dữ liệu BỊ XÓA THẬT! Không phải dry-run!

-- ★ GIẢI PHÁP AN TOÀN: Wrap trong transaction rồi rollback
BEGIN;
EXPLAIN ANALYZE DELETE FROM enrollments WHERE status = 'DROPPED';
ROLLBACK;  -- ← Hoàn tác, dữ liệu an toàn
```

> **Quy tắc sắt đá:** Trên production, LUÔN wrap `EXPLAIN ANALYZE` cho write operations trong `BEGIN...ROLLBACK`. Hoặc dùng `EXPLAIN (ANALYZE, BUFFERS)` chỉ với `SELECT`.

---

## 3.2 — GIN Index: "Vũ khí thần thánh" cho JSONB & ARRAY

### GIN Index là gì?

GIN (Generalized Inverted Index) hoạt động giống như **mục lục ở cuối sách**: thay vì duyệt từng trang, bạn tra mục lục để biết từ khóa xuất hiện ở trang nào.

| Tiêu chí | B-Tree Index | GIN Index |
|-----------|-------------|-----------|
| **Phù hợp cho** | Scalar values (INT, VARCHAR, UUID) | Composite values (JSONB, Array, Full-text) |
| **Operator hỗ trợ** | `=`, `<`, `>`, `BETWEEN` | `@>`, `?`, `?|`, `?&`, `&&`, `@@` |
| **Tốc độ INSERT** | ✅ Nhanh | ⚠️ Chậm hơn (phải update inverted index) |
| **Tốc độ SELECT** | ✅ Nhanh cho exact/range | ✅ Cực nhanh cho containment/search |
| **Kích thước** | Nhỏ | Lớn hơn (vì lưu mọi key/value) |

### Tạo GIN Index cho JSONB

```sql
-- ★ GIN index cho toàn bộ document JSONB
-- Hỗ trợ: @>, ?, ?|, ?&
CREATE INDEX idx_quiz_config_gin 
ON quiz_results USING gin(quiz_config);

-- Giờ query này sẽ dùng index:
EXPLAIN ANALYZE
SELECT * FROM quiz_results
WHERE quiz_config @> '{"passing_score": 70}'::jsonb;
-- → Index Scan using idx_quiz_config_gin (thay vì Seq Scan)
```

```sql
-- ★ GIN index với operator class jsonb_path_ops (nhỏ hơn, nhanh hơn)
-- Chỉ hỗ trợ @> nhưng nhỏ hơn 2-3x so với gin mặc định
CREATE INDEX idx_quiz_config_pathops 
ON quiz_results USING gin(quiz_config jsonb_path_ops);

-- ★ Khi nào dùng cái nào?
-- jsonb_ops (default): Cần ?, ?|, ?& → kiểm tra key tồn tại
-- jsonb_path_ops: Chỉ cần @> → kiểm tra containment (phổ biến hơn 90%)
```

### Tạo GIN Index cho ARRAY

```sql
-- ★ GIN index cho cột tags (TEXT[])
CREATE INDEX idx_lessons_tags_gin 
ON lessons USING gin(tags);

-- Giờ các query sau sẽ cực nhanh:

-- Tìm bài giảng có tag 'spring'
SELECT title FROM lessons WHERE tags @> ARRAY['spring'];
-- → Bitmap Index Scan on idx_lessons_tags_gin

-- Tìm bài giảng có BẤT KỲ tag nào trong danh sách
SELECT title FROM lessons WHERE tags && ARRAY['docker', 'postgresql'];
-- → Bitmap Index Scan on idx_lessons_tags_gin

-- ★ Operator @> (contains) và && (overlap) đều dùng được GIN
```

### Expression Index cho JSONB field cụ thể

```sql
-- Khi bạn chỉ query trên 1 field cụ thể thường xuyên,
-- Expression Index nhỏ gọn hơn GIN toàn document:
CREATE INDEX idx_quiz_passing_score 
ON quiz_results ((quiz_config ->> 'passing_score'));

-- Giờ query này dùng B-Tree index thay vì GIN:
SELECT * FROM quiz_results
WHERE quiz_config ->> 'passing_score' = '70';
```

> **💡 MySQL vs Postgres:** MySQL 8.0 hỗ trợ "Multi-Valued Index" cho JSON array, nhưng cú pháp phức tạp hơn và không mạnh bằng GIN. MySQL không có native ARRAY type nên không có tương đương cho `tags && ARRAY[...]`.

---

## 3.3 — Keyset Pagination: Phân trang Production-Grade

### Vấn đề với OFFSET-LIMIT (cách phổ biến nhưng sai)

```sql
-- Trang 1: Tốt, nhanh
SELECT * FROM courses ORDER BY created_at DESC LIMIT 10 OFFSET 0;

-- Trang 100: CHẬM! Postgres phải đọc 990 rows rồi bỏ đi
SELECT * FROM courses ORDER BY created_at DESC LIMIT 10 OFFSET 990;

-- Trang 10000: CỰC CHẬM! Đọc 99990 rows rồi bỏ đi
SELECT * FROM courses ORDER BY created_at DESC LIMIT 10 OFFSET 99990;
```

> **Bản chất:** `OFFSET N` buộc Postgres scan qua N rows → O(N) performance. Với 1 triệu rows, trang cuối phải scan toàn bộ bảng.

### ★ Keyset Pagination (Cursor-based)

```sql
-- Trang 1: Lấy 10 khóa học mới nhất
SELECT id, title, created_at
FROM courses
WHERE is_published = TRUE
ORDER BY created_at DESC, id DESC
LIMIT 10;

-- Trang 2: Dùng "cursor" là (created_at, id) của row cuối trang trước
-- Giả sử row cuối trang 1: created_at = '2026-01-15', id = 'c1111...'
SELECT id, title, created_at
FROM courses
WHERE is_published = TRUE
  AND (created_at, id) < ('2026-01-15T08:00:00+07'::TIMESTAMPTZ, 'c1111111-1111-1111-1111-111111111111'::UUID)
ORDER BY created_at DESC, id DESC
LIMIT 10;
```

**Tại sao nhanh?** Postgres dùng index `(created_at DESC, id DESC)` để nhảy thẳng đến vị trí cursor, không scan rows trước đó. O(1) cho mọi trang!

### Index hỗ trợ Keyset Pagination

```sql
-- Composite index cho pagination
CREATE INDEX idx_courses_pagination 
ON courses(created_at DESC, id DESC)
WHERE is_published = TRUE;  -- ★ Partial index: chỉ index khóa học published
```

### Spring Boot Implementation

```java
// DTO cho Keyset Pagination
public record CoursePageRequest(
    OffsetDateTime lastCreatedAt,  // null cho trang đầu tiên
    UUID lastId,                    // null cho trang đầu tiên
    int size
) {}

public record CoursePageResponse(
    List<CourseDTO> courses,
    boolean hasNext,
    OffsetDateTime nextCreatedAt,  // cursor cho trang tiếp
    UUID nextId                     // cursor cho trang tiếp
) {}

// Repository
@Repository
public interface CourseRepository extends JpaRepository<Course, UUID> {

    // Trang đầu tiên
    @Query(value = """
        SELECT * FROM courses 
        WHERE is_published = TRUE
        ORDER BY created_at DESC, id DESC 
        LIMIT :size
        """, nativeQuery = true)
    List<Course> findFirstPage(@Param("size") int size);

    // Các trang tiếp theo (keyset)
    @Query(value = """
        SELECT * FROM courses 
        WHERE is_published = TRUE
          AND (created_at, id) < (:lastCreatedAt, CAST(:lastId AS UUID))
        ORDER BY created_at DESC, id DESC 
        LIMIT :size
        """, nativeQuery = true)
    List<Course> findNextPage(
        @Param("lastCreatedAt") OffsetDateTime lastCreatedAt,
        @Param("lastId") String lastId,
        @Param("size") int size
    );
}

// Service
@Service
public class CourseService {

    public CoursePageResponse getCourses(CoursePageRequest request) {
        int fetchSize = request.size() + 1; // +1 để check hasNext
        
        List<Course> courses;
        if (request.lastCreatedAt() == null) {
            courses = courseRepository.findFirstPage(fetchSize);
        } else {
            courses = courseRepository.findNextPage(
                request.lastCreatedAt(), 
                request.lastId().toString(), 
                fetchSize
            );
        }
        
        boolean hasNext = courses.size() > request.size();
        if (hasNext) {
            courses = courses.subList(0, request.size()); // Bỏ row thừa
        }
        
        Course lastCourse = courses.isEmpty() ? null : courses.get(courses.size() - 1);
        return new CoursePageResponse(
            courses.stream().map(this::toDTO).toList(),
            hasNext,
            lastCourse != null ? lastCourse.getCreatedAt() : null,
            lastCourse != null ? lastCourse.getId() : null
        );
    }
}
```

---

## 🎯 GÓC PHỎNG VẤN — PHẦN 3

### ❓ Câu 1: "EXPLAIN và EXPLAIN ANALYZE khác nhau thế nào? Tại sao EXPLAIN ANALYZE nguy hiểm trên production?"

> **💬 Câu trả lời sắc sảo:**
>
> "**EXPLAIN** chỉ hiện query plan **dự kiến** của planner — bao gồm loại scan (Seq Scan, Index Scan), join strategy (Hash Join, Nested Loop), estimated rows và cost. Nó **không thực sự chạy** query.
>
> **EXPLAIN ANALYZE** chạy query **thật sự** và bổ sung `actual time`, `actual rows`, `loops`, `Buffers` (shared hit/read). Nhờ đó em có thể phát hiện khi planner ước lượng sai (estimated 10 rows nhưng actual 100,000 rows → cần `ANALYZE` lại statistics).
>
> **Nguy hiểm:** Vì `EXPLAIN ANALYZE` chạy thật, nếu query là `DELETE` hoặc `UPDATE`, dữ liệu **bị thay đổi thật**. Ví dụ: `EXPLAIN ANALYZE DELETE FROM enrollments WHERE status = 'DROPPED'` sẽ xóa dữ liệu!
>
> **Giải pháp an toàn:** Wrap trong transaction:
> ```sql
> BEGIN;
> EXPLAIN ANALYZE DELETE FROM enrollments WHERE status = 'DROPPED';
> ROLLBACK; -- dữ liệu được phục hồi
> ```
>
> Hoặc trên production, em chỉ dùng `EXPLAIN ANALYZE` với `SELECT`. Cho write operations, em dùng `EXPLAIN` (không ANALYZE) để xem plan, hoặc test trên staging."

---

### ❓ Câu 2: "GIN Index khác B-Tree Index như thế nào? Khi nào anh/chị dùng GIN?"

> **💬 Câu trả lời sắc sảo:**
>
> "**B-Tree** là index mặc định, tổ chức dữ liệu theo **cây cân bằng** — phù hợp cho so sánh scalar: `=`, `<`, `>`, `BETWEEN`, `ORDER BY`. Mỗi leaf node trỏ đến đúng 1 row.
>
> **GIN** (Generalized Inverted Index) tổ chức theo kiểu **inverted index** — giống index cuối sách — mỗi 'từ khóa' (key trong JSONB, element trong array, lexeme trong tsvector) trỏ đến **tập hợp các rows** chứa từ khóa đó. Phù hợp cho: `@>` (contains), `?` (key exists), `&&` (overlap), `@@` (full-text search).
>
> **Trong E-Learning em dùng GIN cho:**
> 1. `quiz_config JSONB` — tìm quiz theo config: `WHERE quiz_config @> '{"passing_score": 70}'`
> 2. `tags TEXT[]` — tìm lessons theo tag: `WHERE tags @> ARRAY['spring']`
>
> **Trade-off:** GIN insert chậm hơn B-Tree (vì phải update inverted list cho mọi key), và chiếm dung lượng lớn hơn. Nhưng cho workload **read-heavy** của E-Learning (đọc nhiều, ghi ít), GIN là lựa chọn tối ưu.
>
> Em cũng dùng `jsonb_path_ops` thay cho `jsonb_ops` mặc định khi chỉ cần operator `@>` — giảm kích thước index 2-3 lần."

---

### ❓ Câu 3: "Keyset Pagination khác gì OFFSET/LIMIT? Khi nào anh/chị chọn cách nào?"

> **💬 Câu trả lời sắc sảo:**
>
> "**OFFSET/LIMIT** phải scan qua N rows rồi bỏ đi → trang càng sâu càng chậm. Trang 1000 phải scan 10,000 rows. Đây là O(OFFSET).
>
> **Keyset Pagination** dùng giá trị của row cuối trang trước làm 'cursor', query `WHERE (col1, col2) < (last_val1, last_val2)`. Postgres nhảy thẳng đến vị trí đó bằng index → O(1) cho mọi trang.
>
> | | OFFSET/LIMIT | Keyset |
> |---|---|---|
> | Trang đầu | Nhanh | Nhanh |
> | Trang 1000 | Chậm (scan 10K rows) | Nhanh (index seek) |
> | Nhảy đến trang bất kỳ | ✅ Có thể | ❌ Không (chỉ next/prev) |
> | Data consistency khi INSERT/DELETE | ❌ Rows bị lặp/mất | ✅ Ổn định |
>
> **Em chọn Keyset cho:**
> - API endpoint danh sách khóa học (infinite scroll, mobile app)
> - Mọi trang có > 10,000 rows
>
> **Em chọn OFFSET cho:**
> - Admin panel cần nhảy đến trang bất kỳ (và dataset nhỏ < 10K rows)
> - Báo cáo nội bộ không cần performance cao
>
> **Lưu ý:** Keyset cần composite index phù hợp. Ví dụ: `CREATE INDEX ON courses(created_at DESC, id DESC)` cho pagination sort theo thời gian."

---

# PHẦN 4: CONCURRENCY & BÀI TOÁN GHI DANH KHÓA HỌC

## 4.1 — Kịch bản Race Condition: Ghi danh vượt quá giới hạn

### Mô tả bài toán

```
Khóa học "PostgreSQL Mastery" có max_students = 30.
Hiện tại đã có 29 học viên đăng ký (ACTIVE + COMPLETED).
HAI học viên (Linh & Anh) cùng bấm nút "Đăng ký" ở cùng 1 thời điểm.

Kỳ vọng: Chỉ 1 người được đăng ký. Người còn lại nhận thông báo "Hết suất".
Thực tế nếu không xử lý: CẢ HAI đều đăng ký thành công → 31 học viên (vi phạm).
```

### Tại sao xảy ra Race Condition?

```
Timeline:
────────────────────────────────────────────────────────────
Transaction A (Linh)           Transaction B (Anh)
────────────────────────────────────────────────────────────
BEGIN;                         BEGIN;
                               
SELECT COUNT(*) = 29           SELECT COUNT(*) = 29
(29 < 30 → OK, cho đăng ký)   (29 < 30 → OK, cho đăng ký)
                               
INSERT enrollment (Linh)       INSERT enrollment (Anh)
                               
COMMIT; → 30 students ✓        COMMIT; → 31 students ✗ ← BUG!
────────────────────────────────────────────────────────────
```

Cả hai transaction đều đọc COUNT = 29 trước khi bên nào INSERT. Đây là **Lost Update** / **Write Skew**.

### ★ Giải pháp 1: Row-Level Lock với `SELECT ... FOR UPDATE`

```sql
-- ★ Transaction xử lý ghi danh an toàn
BEGIN;

-- Bước 1: Lock row của khóa học → chặn transaction khác đọc cùng row
SELECT id, max_students
FROM courses
WHERE id = 'c2222222-2222-2222-2222-222222222222'
FOR UPDATE;  -- ★ Khóa row-level, transaction khác phải ĐỢI

-- Bước 2: Đếm số enrollment hiện tại (an toàn vì row đã bị lock)
SELECT COUNT(*) AS current_count
FROM enrollments
WHERE course_id = 'c2222222-2222-2222-2222-222222222222'
  AND status IN ('ACTIVE', 'COMPLETED');

-- Bước 3: Nếu current_count < max_students → INSERT
-- Ngược lại → ROLLBACK hoặc raise exception
INSERT INTO enrollments (student_id, course_id, status)
VALUES ('b4444444-4444-4444-4444-444444444444', 
        'c2222222-2222-2222-2222-222222222222', 
        'ACTIVE');

COMMIT;
```

### Giải thích cơ chế FOR UPDATE

```
Timeline SỬA LỖI:
────────────────────────────────────────────────────────────
Transaction A (Linh)              Transaction B (Anh)
────────────────────────────────────────────────────────────
BEGIN;                            BEGIN;
                                  
SELECT ... FOR UPDATE             SELECT ... FOR UPDATE
→ Lock row course 'c222...'      → ⏳ BLOCKED! Chờ A release lock
→ COUNT = 29 → OK                
                                  
INSERT enrollment (Linh)          (vẫn đang chờ...)
                                  
COMMIT; → Release lock            → Lock acquired!
         → 30 students ✓          → COUNT = 30 → 30 ≥ 30 → REJECT!
                                  
                                  ROLLBACK; → "Hết suất" ✓
────────────────────────────────────────────────────────────
```

### ★ Giải pháp 2: Advisory Lock (ít khóa hơn, production-grade)

```sql
-- Advisory Lock dùng course_id hash làm lock key
-- Không lock row thật → ít contention hơn FOR UPDATE
BEGIN;

-- pg_advisory_xact_lock tự giải phóng khi transaction kết thúc
SELECT pg_advisory_xact_lock(hashtext('c2222222-2222-2222-2222-222222222222'));

-- Bây giờ an toàn để check & insert
SELECT COUNT(*) FROM enrollments
WHERE course_id = 'c2222222-2222-2222-2222-222222222222'
  AND status IN ('ACTIVE', 'COMPLETED');

-- INSERT nếu chưa đầy...

COMMIT;
```

### Spring Boot Implementation: Pessimistic Lock

```java
// ★ Entity
@Entity
@Table(name = "courses")
public class Course {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    
    @Column(name = "max_students")
    private Integer maxStudents;
    
    // ... other fields
}

// ★ Repository: Sử dụng @Lock annotation
@Repository
public interface CourseRepository extends JpaRepository<Course, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)  // ★ Tương đương FOR UPDATE
    @Query("SELECT c FROM Course c WHERE c.id = :courseId")
    Optional<Course> findByIdForUpdate(@Param("courseId") UUID courseId);
}

// ★ Repository: Đếm enrollment
@Repository
public interface EnrollmentRepository extends JpaRepository<Enrollment, UUID> {

    @Query("""
        SELECT COUNT(e) FROM Enrollment e 
        WHERE e.course.id = :courseId 
          AND e.status IN ('ACTIVE', 'COMPLETED')
        """)
    long countActiveByCourseId(@Param("courseId") UUID courseId);
    
    boolean existsByStudentIdAndCourseId(UUID studentId, UUID courseId);
}

// ★ Service: Logic ghi danh an toàn
@Service
@RequiredArgsConstructor
public class EnrollmentService {

    private final CourseRepository courseRepository;
    private final EnrollmentRepository enrollmentRepository;
    private final UserRepository userRepository;

    @Transactional  // ★ BẮT BUỘC phải có — lock chỉ hoạt động trong transaction
    public EnrollmentResult enroll(UUID studentId, UUID courseId) {
        
        // 1. Kiểm tra student tồn tại
        User student = userRepository.findById(studentId)
            .orElseThrow(() -> new NotFoundException("Student not found"));
        
        // 2. Lock course row (FOR UPDATE)
        Course course = courseRepository.findByIdForUpdate(courseId)
            .orElseThrow(() -> new NotFoundException("Course not found"));
        
        // 3. Kiểm tra đã đăng ký chưa
        if (enrollmentRepository.existsByStudentIdAndCourseId(studentId, courseId)) {
            throw new BusinessException("Bạn đã đăng ký khóa học này rồi");
        }
        
        // 4. Đếm enrollment hiện tại (AN TOÀN vì row đã lock)
        long currentCount = enrollmentRepository.countActiveByCourseId(courseId);
        
        if (currentCount >= course.getMaxStudents()) {
            throw new BusinessException("Khóa học đã đầy (" + 
                course.getMaxStudents() + "/" + course.getMaxStudents() + ")");
        }
        
        // 5. Tạo enrollment mới
        Enrollment enrollment = new Enrollment();
        enrollment.setStudent(student);
        enrollment.setCourse(course);
        enrollment.setStatus(EnrollmentStatus.ACTIVE);
        enrollment.setEnrolledAt(OffsetDateTime.now());
        
        enrollmentRepository.save(enrollment);
        
        return new EnrollmentResult(
            true, 
            "Đăng ký thành công! Suất còn lại: " + 
            (course.getMaxStudents() - currentCount - 1)
        );
    }
}
```

> **⚠️ Lưu ý quan trọng:** Nếu thiếu `@Transactional`, lock `FOR UPDATE` không hoạt động vì mỗi query chạy trong auto-commit riêng biệt. Đây là lỗi phổ biến nhất của Junior dev khi dùng Pessimistic Lock.

---

## 4.2 — Isolation Levels: Tại sao Postgres xử lý Phantom Read tốt hơn?

### Bảng so sánh Isolation Levels

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read |
|-----------------|-----------|---------------------|-------------|
| **READ UNCOMMITTED** | Có thể | Có thể | Có thể |
| **READ COMMITTED** (Postgres default) | ❌ Không | Có thể | Có thể |
| **REPEATABLE READ** | ❌ Không | ❌ Không | ⭐ Xem phân tích |
| **SERIALIZABLE** | ❌ Không | ❌ Không | ❌ Không |

### ★ Điểm khác biệt then chốt: REPEATABLE READ

**Theo chuẩn SQL:** `REPEATABLE READ` vẫn **cho phép** Phantom Read (một transaction thấy rows mới được INSERT bởi transaction khác).

**Postgres (nhờ MVCC - Multi-Version Concurrency Control):**
- Mỗi transaction nhìn thấy **snapshot** của dữ liệu tại thời điểm bắt đầu transaction.
- Rows được INSERT/UPDATE bởi transaction khác **KHÔNG xuất hiện** trong snapshot → **Phantom Read KHÔNG XẢY RA** ở `REPEATABLE READ`.

> **Đây chính là lý do Postgres được coi là 'strict' hơn chuẩn SQL ở mức REPEATABLE READ.**

### Ví dụ minh họa

```sql
-- ★ DEMO PHANTOM READ (mở 2 terminal psql)

-- Terminal 1:
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) FROM enrollments WHERE course_id = 'c1111111-1111-1111-1111-111111111111';
-- Kết quả: 3

-- Terminal 2 (trong lúc Terminal 1 chưa COMMIT):
INSERT INTO enrollments (student_id, course_id, status)
VALUES ('b6666666-6666-6666-6666-666666666666', 'c1111111-1111-1111-1111-111111111111', 'ACTIVE');
COMMIT;

-- Quay lại Terminal 1:
SELECT COUNT(*) FROM enrollments WHERE course_id = 'c1111111-1111-1111-1111-111111111111';
-- Kết quả VẪN LÀ 3! ★ Không bị Phantom Read
-- (MySQL InnoDB ở REPEATABLE READ cũng dùng MVCC nên cũng ngăn được,
--  nhưng chỉ cho SELECT thông thường. Với SELECT ... FOR UPDATE, MySQL
--  chuyển sang current read và có thể thấy phantom.)

COMMIT;
```

### MVCC hoạt động như thế nào?

```
★ Postgres MVCC - Mỗi row có 2 "mốc thời gian ẩn":
┌──────────────────────────────────────────────────┐
│  Row Data  │  xmin (created by TX)  │  xmax (deleted/updated by TX)  │
├──────────────────────────────────────────────────┤
│  Enrollment│  TX 100               │  0 (chưa bị xóa)              │
│  Enrollment│  TX 105               │  0 (chưa bị xóa)              │
│  Enrollment│  TX 110 (new insert)  │  0                             │
└──────────────────────────────────────────────────┘

Transaction A (bắt đầu tại snapshot TX 108):
→ Chỉ thấy rows có xmin <= 108 VÀ xmax = 0 hoặc xmax > 108
→ Row mới (xmin = 110) KHÔNG nằm trong snapshot → PHANTOM READ bị CHẶN
```

### So sánh Postgres vs MySQL (InnoDB) về MVCC

| Tiêu chí | PostgreSQL MVCC | MySQL InnoDB MVCC |
|-----------|-----------------|-------------------|
| **Lưu trữ version** | Trong cùng tablespace (heap) | Undo log riêng biệt |
| **Dead tuple** | Cần `VACUUM` dọn dẹp | Purge thread tự động |
| **REPEATABLE READ** | Snapshot từ đầu transaction | Snapshot từ **câu SELECT đầu tiên** |
| **Phantom ở RR** | ❌ Chặn hoàn toàn (consistent snapshot) | ⚠️ Chặn cho snapshot read, nhưng current read (`FOR UPDATE`) có thể thấy phantom |
| **Serialization failure** | Raise error → app retry | Gap lock → có thể deadlock |

---

## 🎯 GÓC PHỎNG VẤN — PHẦN 4

### ❓ Câu 1: "Mô tả một kịch bản Race Condition trong hệ thống E-Learning và cách anh/chị giải quyết."

> **💬 Câu trả lời sắc sảo:**
>
> "**Kịch bản:** Khóa học 'PostgreSQL Mastery' giới hạn 30 suất, hiện có 29 người. Hai học viên cùng bấm 'Đăng ký' đồng thời.
>
> **Vấn đề:** Cả hai transaction đều đọc COUNT = 29 (< 30 → OK), rồi cả hai INSERT → 31 học viên. Đây là **Write Skew** — một dạng race condition xảy ra khi 2 transactions đọc cùng dữ liệu, ra quyết định dựa trên đó, rồi ghi mà không biết về nhau.
>
> **Giải pháp em dùng: `SELECT ... FOR UPDATE` (Pessimistic Lock)**
>
> 1. Trước khi check COUNT, em lock row của course bằng `SELECT ... FOR UPDATE`
> 2. Transaction thứ hai bị **block** cho đến khi transaction thứ nhất commit/rollback
> 3. Khi được release lock, transaction thứ hai đọc COUNT = 30 → reject
>
> **Trong Spring Boot:** Em dùng `@Lock(LockModeType.PESSIMISTIC_WRITE)` trên repository method và **bắt buộc** có `@Transactional` trên service method. Thiếu `@Transactional` là lỗi phổ biến nhất — lock không hoạt động vì mỗi query auto-commit riêng biệt.
>
> **Tại sao không dùng Optimistic Lock?** Vì kịch bản này có **high contention** (nhiều người đăng ký cùng lúc, đặc biệt khi khóa học sắp đầy). Optimistic Lock sẽ gây **nhiều retry** → trải nghiệm người dùng kém. Pessimistic Lock đảm bảo **chỉ 1 transaction xử lý tại 1 thời điểm** — đơn giản và chính xác."

---

### ❓ Câu 2: "PostgreSQL xử lý Phantom Read ở mức REPEATABLE READ khác gì so với chuẩn SQL? Giải thích cơ chế."

> **💬 Câu trả lời sắc sảo:**
>
> "**Chuẩn SQL** cho phép Phantom Read ở `REPEATABLE READ` — nghĩa là transaction có thể thấy rows mới được INSERT bởi transaction khác.
>
> **PostgreSQL** nhờ cơ chế **MVCC (Multi-Version Concurrency Control)** đã ngăn chặn Phantom Read ngay ở mức `REPEATABLE READ`, vượt chuẩn SQL:
>
> - Khi transaction bắt đầu ở `REPEATABLE READ`, Postgres tạo một **snapshot** tại thời điểm câu lệnh đầu tiên trong transaction.
> - Mọi rows được INSERT/UPDATE/DELETE bởi transactions khác **sau** snapshot đều **vô hình** với transaction hiện tại.
> - Cơ chế: mỗi row có trường ẩn `xmin` (transaction tạo row) và `xmax` (transaction xóa/update row). Transaction chỉ thấy rows có `xmin` nằm trong snapshot.
>
> **So sánh MySQL InnoDB:** MySQL InnoDB cũng dùng MVCC nhưng có sự khác biệt: **snapshot read** (SELECT thông thường) được bảo vệ khỏi phantom, nhưng **current read** (`SELECT ... FOR UPDATE`, `SELECT ... LOCK IN SHARE MODE`) đọc dữ liệu mới nhất → có thể thấy phantom. Postgres thì nhất quán: cả snapshot read và locking read đều dựa trên snapshot.
>
> **Hệ quả thực tiễn:** Postgres ở `REPEATABLE READ` gần như tương đương `SERIALIZABLE` ở nhiều RDBMS khác. Tuy nhiên, `SERIALIZABLE` của Postgres bổ sung thêm **Serializable Snapshot Isolation (SSI)** để phát hiện write skew — điều mà `REPEATABLE READ` không làm."

---

### ❓ Câu 3: "Phân biệt Pessimistic Lock và Optimistic Lock. Trong dự án E-Learning, anh/chị dùng cái nào ở đâu?"

> **💬 Câu trả lời sắc sảo:**
>
> | | Pessimistic Lock | Optimistic Lock |
> |---|---|---|
> | **Cơ chế** | Lock row trước khi đọc (`FOR UPDATE`) | Không lock, check version khi UPDATE |
> | **Khi nào block** | Ngay lập tức khi có conflict | Chỉ khi COMMIT (throw `OptimisticLockException`) |
> | **Phù hợp** | High contention (nhiều conflict) | Low contention (ít conflict) |
> | **Trong JPA** | `@Lock(PESSIMISTIC_WRITE)` | `@Version` trên entity |
>
> **Trong E-Learning, em phân chia như sau:**
>
> 1. **Pessimistic Lock cho ghi danh khóa học** — vì khi khóa học sắp đầy, nhiều người đăng ký đồng thời → high contention. Lock row course để đảm bảo chỉ 1 transaction check-and-insert tại 1 thời điểm.
>
> 2. **Optimistic Lock cho cập nhật thông tin khóa học** — giảng viên sửa tiêu đề, mô tả. Rất ít khi 2 người cùng sửa 1 khóa → low contention. Em thêm `@Version` trên entity Course:
>
> ```java
> @Version
> private Long version; // Hibernate tự tăng và check khi UPDATE
> ```
>
> Nếu 2 giảng viên cùng sửa, người sau sẽ nhận `OptimisticLockException` → em catch và hiển thị: 'Dữ liệu đã bị thay đổi, vui lòng tải lại'.
>
> 3. **Không cần lock cho quiz submission** — mỗi học viên nộp bài quiz riêng, không conflict với ai → chỉ cần `UNIQUE(student_id, course_id)` constraint."

---

# PHẦN 5: BÀI TEST PHỎNG VẤN TỔNG HỢP (MOCK INTERVIEW)

> **Hướng dẫn:** Đọc kỹ từng tình huống, suy luận nguyên nhân, và trình bày giải pháp theo chuẩn **STAR** (Situation - Task - Action - Result). Hãy tự viết câu trả lời trước khi xem đáp án gợi ý.

---

## 🔥 Tình huống 1: "Query Dashboard Chậm Dần Theo Thời Gian"

### Mô tả

```
SITUATION:
Hệ thống E-Learning có trang Dashboard cho Admin hiển thị:
- Tổng doanh thu theo tháng
- Top 10 khóa học bán chạy nhất
- Số học viên mới đăng ký tuần này

Sau 6 tháng vận hành, trang Dashboard mất 12 giây để load (ban đầu < 1 giây).
Bảng enrollments đã có 500,000 rows, quiz_results có 2 triệu rows.
```

### Yêu cầu

Phân tích nguyên nhân và đưa ra giải pháp theo STAR.

### Đáp án gợi ý

> **TASK:** Giảm thời gian load Dashboard từ 12s xuống dưới 1s mà không thay đổi logic business.
>
> **ACTION:**
>
> **A1. Chẩn đoán bằng EXPLAIN ANALYZE:**
> ```sql
> EXPLAIN (ANALYZE, BUFFERS) 
> SELECT DATE_TRUNC('month', e.enrolled_at) AS month, 
>        SUM(c.price) AS revenue
> FROM enrollments e
> JOIN courses c ON e.course_id = c.id
> WHERE e.status IN ('ACTIVE', 'COMPLETED')
> GROUP BY month ORDER BY month;
> ```
> → Phát hiện: **Seq Scan** trên enrollments (500K rows), không có index trên `enrolled_at`.
>
> **A2. Tạo Composite Index + Partial Index:**
> ```sql
> CREATE INDEX idx_enrollments_date_status 
> ON enrollments(enrolled_at DESC, course_id)
> WHERE status IN ('ACTIVE', 'COMPLETED');
> ```
>
> **A3. Sử dụng Materialized View cho báo cáo:**
> ```sql
> CREATE MATERIALIZED VIEW mv_monthly_revenue AS
> SELECT DATE_TRUNC('month', e.enrolled_at) AS month,
>        c.id AS course_id, c.title,
>        COUNT(*) AS students, SUM(c.price) AS revenue
> FROM enrollments e
> JOIN courses c ON e.course_id = c.id
> WHERE e.status IN ('ACTIVE', 'COMPLETED')
> GROUP BY month, c.id, c.title;
> 
> CREATE UNIQUE INDEX ON mv_monthly_revenue(month, course_id);
> 
> -- Refresh mỗi 15 phút bằng pg_cron hoặc @Scheduled trong Spring Boot
> REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_revenue;
> ```
>
> **A4. Kiểm tra table bloat & VACUUM:**
> ```sql
> -- Nếu bảng bị bloat (dead tuples nhiều), VACUUM ANALYZE
> SELECT relname, n_dead_tup, n_live_tup, 
>        ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup, 0), 2) AS dead_pct
> FROM pg_stat_user_tables 
> WHERE relname = 'enrollments';
> 
> VACUUM ANALYZE enrollments;
> ```
>
> **RESULT:** Dashboard load time giảm từ 12s → 200ms. Materialized View được refresh mỗi 15 phút, đáp ứng yêu cầu "near real-time" của Admin Dashboard.

---

## 🔥 Tình huống 2: "Deadlock khi Đăng ký Nhiều Khóa Học Cùng Lúc"

### Mô tả

```
SITUATION:
Hệ thống cho phép đăng ký "Combo khóa học" — 1 lần bấm đăng ký 3 khóa.
Log server ghi nhận lỗi Deadlock liên tục:
  ERROR: deadlock detected
  DETAIL: Process 12345 waits for ShareLock on transaction 67890;
          blocked by process 67891.
          Process 67891 waits for ShareLock on transaction 12345;
          blocked by process 12345.
          
Xảy ra khi nhiều học viên đăng ký combo cùng thời điểm.
```

### Yêu cầu

Giải thích nguyên nhân Deadlock và cách fix.

### Đáp án gợi ý

> **TASK:** Loại bỏ Deadlock mà vẫn đảm bảo tính toàn vẹn ghi danh combo.
>
> **ACTION:**
>
> **A1. Phân tích nguyên nhân:**
> ```
> Transaction A: Lock Course X → Lock Course Y → Lock Course Z
> Transaction B: Lock Course Y → Lock Course X → ...
> → A giữ X, chờ Y. B giữ Y, chờ X. → DEADLOCK!
> ```
> Nguyên nhân: Các transaction lock courses theo **thứ tự khác nhau** (tùy thuộc vào thứ tự combo mà user chọn).
>
> **A2. Fix: Sắp xếp thứ tự lock theo UUID (Canonical Ordering):**
> ```java
> @Transactional
> public void enrollCombo(UUID studentId, List<UUID> courseIds) {
>     // ★ SẮP XẾP courseIds để mọi transaction lock CÙNG THỨ TỰ
>     List<UUID> sortedIds = courseIds.stream().sorted().toList();
>     
>     for (UUID courseId : sortedIds) {
>         // Lock theo thứ tự UUID tăng dần → KHÔNG BAO GIỜ deadlock
>         Course course = courseRepository.findByIdForUpdate(courseId)
>             .orElseThrow();
>         // ... check capacity, insert enrollment
>     }
> }
> ```
>
> **A3. Quy tắc vàng:** Khi cần lock nhiều resources, **LUÔN lock theo thứ tự cố định** (sort by ID). Đây là kỹ thuật kinh điển ngăn deadlock trong mọi hệ thống.
>
> **RESULT:** Sau khi sort courseIds trước khi lock, deadlock **hoàn toàn biến mất**. Throughput tăng 3x vì không còn transaction bị abort và retry do deadlock.

---

## 🔥 Tình huống 3: "Full-Text Search Bài Giảng Quá Chậm"

### Mô tả

```
SITUATION:
Thanh tìm kiếm trên trang E-Learning cho phép học viên tìm bài giảng 
theo tiêu đề và nội dung. Query hiện tại dùng LIKE:

SELECT * FROM lessons WHERE title ILIKE '%spring boot%' OR content ILIKE '%spring boot%';

Bảng lessons có 100,000 rows. Query mất 3-5 giây.
EXPLAIN cho thấy Seq Scan trên toàn bộ bảng.
```

### Yêu cầu

Đề xuất giải pháp sử dụng các "vũ khí" của PostgreSQL.

### Đáp án gợi ý

> **TASK:** Giảm thời gian tìm kiếm từ 3-5s xuống < 50ms.
>
> **ACTION:**
>
> **A1. Sử dụng Full-Text Search native của Postgres (tsvector + tsquery):**
> ```sql
> -- Thêm cột tsvector (computed column)
> ALTER TABLE lessons ADD COLUMN search_vector tsvector
>     GENERATED ALWAYS AS (
>         setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
>         setweight(to_tsvector('simple', coalesce(content, '')), 'B')
>     ) STORED;
> -- ★ Weight 'A' cho title (ưu tiên cao), 'B' cho content
> 
> -- Tạo GIN index trên cột tsvector
> CREATE INDEX idx_lessons_search ON lessons USING gin(search_vector);
> 
> -- Query tìm kiếm cực nhanh
> SELECT title, 
>        ts_rank(search_vector, query) AS relevance
> FROM lessons, 
>      to_tsquery('simple', 'spring & boot') AS query
> WHERE search_vector @@ query
> ORDER BY relevance DESC;
> ```
>
> **A2. Kết hợp tìm kiếm trên tags (ARRAY) + title:**
> ```sql
> -- Tìm lessons có tag 'spring' HOẶC title chứa 'spring'
> SELECT title, tags
> FROM lessons
> WHERE tags @> ARRAY['spring']
>    OR search_vector @@ to_tsquery('simple', 'spring');
> ```
>
> **A3. Trigram Index cho fuzzy search (tìm gần đúng):**
> ```sql
> CREATE EXTENSION IF NOT EXISTS pg_trgm;
> CREATE INDEX idx_lessons_title_trgm ON lessons USING gin(title gin_trgm_ops);
> 
> -- Tìm kiếm gần đúng (typo-tolerant)
> SELECT title, similarity(title, 'sprig boot') AS sim
> FROM lessons
> WHERE title % 'sprig boot'  -- % là operator tương đồng
> ORDER BY sim DESC;
> ```
>
> **RESULT:** Query tìm kiếm giảm từ 3-5s xuống 10-30ms nhờ GIN index trên tsvector. Trigram index bổ sung khả năng fuzzy search — khi học viên gõ sai chính tả, hệ thống vẫn trả về kết quả phù hợp.

---

## 🔥 Tình huống 4: "Connection Pool Cạn Kiệt Vào Giờ Cao Điểm"

### Mô tả

```
SITUATION:
Hệ thống E-Learning có 500 học viên online cùng lúc vào buổi tối (19h-22h).
Spring Boot cấu hình HikariCP maxPoolSize = 10.
Log liên tục báo:
  HikariPool-1 - Connection is not available, request timed out after 30000ms
  
Postgres server: max_connections = 100, CPU idle 80%, RAM dư 60%.
→ Database KHÔNG phải bottleneck, nhưng application không lấy được connection.
```

### Yêu cầu

Phân tích nguyên nhân và đề xuất giải pháp toàn diện.

### Đáp án gợi ý

> **TASK:** Giải quyết connection exhaustion mà không đơn giản chỉ tăng pool size.
>
> **ACTION:**
>
> **A1. Phân tích nguyên nhân gốc rễ:**
> ```
> 500 concurrent users × 1 request/user = 500 concurrent requests
> Mỗi request giữ connection trong transaction = ~200ms
> Throughput tối đa = 10 connections × (1000ms / 200ms) = 50 requests/second
> Nhưng cần phục vụ 500 users → THIẾU connection
> ```
>
> **A2. Tối ưu application layer:**
> ```yaml
> # application.yml - HikariCP tuning
> spring:
>   datasource:
>     hikari:
>       maximum-pool-size: 20          # Tăng hợp lý (KHÔNG tăng quá 30)
>       minimum-idle: 5
>       connection-timeout: 10000      # 10s thay vì 30s (fail fast)
>       idle-timeout: 300000           # 5 phút
>       max-lifetime: 600000           # 10 phút
>       leak-detection-threshold: 5000 # ★ Phát hiện connection leak (> 5s)
> ```
>
> **A3. Tìm và fix connection leak:**
> ```java
> // ❌ SAI: Mở transaction quá lâu (gọi external API trong transaction)
> @Transactional
> public void processEnrollment(UUID studentId, UUID courseId) {
>     enrollmentRepository.save(enrollment);
>     paymentService.callExternalPaymentAPI(orderId); // ★ 2-5 giây!
>     // Connection bị giữ suốt thời gian gọi API
> }
> 
> // ✅ ĐÚNG: Tách external call ra ngoài transaction
> public void processEnrollment(UUID studentId, UUID courseId) {
>     // Transaction 1: DB operations (nhanh)
>     enrollInTransaction(studentId, courseId);
>     // External call: KHÔNG giữ connection
>     paymentService.callExternalPaymentAPI(orderId);
> }
> 
> @Transactional
> protected void enrollInTransaction(UUID studentId, UUID courseId) {
>     enrollmentRepository.save(enrollment);
>     // Transaction kết thúc ngay → trả connection về pool
> }
> ```
>
> **A4. Sử dụng PgBouncer (Connection Pooler):**
> ```
> [Application] → [PgBouncer (port 6432)] → [PostgreSQL (port 5432)]
>                  ↑ Pool 200 connections      ↑ max_connections = 100
>                  ↑ Transaction mode           
> ```
> PgBouncer ở chế độ `transaction` sẽ **tái sử dụng** connection giữa các transaction. 200 application connections → chỉ cần 20-30 Postgres connections thực tế.
>
> **A5. Query optimization — giảm thời gian giữ connection:**
> ```sql
> -- ❌ Query chậm giữ connection lâu
> SELECT * FROM courses c 
> LEFT JOIN lessons l ON c.id = l.course_id  -- N+1 nếu lazy load
> WHERE c.is_published = TRUE;
> 
> -- ✅ Batch fetch, giảm round-trip
> @EntityGraph(attributePaths = {"lessons"})
> @Query("SELECT c FROM Course c WHERE c.isPublished = true")
> List<Course> findPublishedCoursesWithLessons();
> ```
>
> **RESULT:**
> 1. Tăng pool size từ 10 → 20, kết hợp fix connection leak → throughput tăng 4x
> 2. Deploy PgBouncer → 500 app connections chia sẻ 30 Postgres connections
> 3. Không còn timeout error, response time P99 < 500ms
>
> **Bài học:** *"Đừng bao giờ tăng pool size như giải pháp đầu tiên. Tìm connection leak trước, tối ưu transaction scope, rồi mới tuning pool size. Tăng pool size chỉ che giấu vấn đề."*

---

## 📋 CHECKLIST TRƯỚC KHI ĐI PHỎNG VẤN

```
✅ Giải thích được UUID vs Auto Increment (ưu/nhược/khi nào dùng)
✅ Viết được query JSONB cơ bản (->>, @>, #>>)
✅ Giải thích JSONB vs JSON (khi nào dùng cái nào)
✅ Viết được CTE thay thế subquery
✅ Viết được Window Function (RANK, DENSE_RANK, ROW_NUMBER)
✅ Đọc được EXPLAIN ANALYZE output (Seq Scan vs Index Scan, actual rows)
✅ Giải thích GIN Index vs B-Tree (khi nào dùng GIN)
✅ Giải thích Keyset Pagination vs OFFSET/LIMIT
✅ Giải thích Race Condition và cách dùng FOR UPDATE
✅ Phân biệt Pessimistic vs Optimistic Lock
✅ Giải thích MVCC và tại sao Postgres REPEATABLE READ tốt hơn chuẩn SQL
✅ Biết khi nào dùng Materialized View
✅ Hiểu Connection Pool và cách tránh connection leak
✅ Map UUID, JSONB, ARRAY, ENUM với Spring Boot Entity
```

---

> **🎓 Lời kết từ "Senior DBA":**
>
> PostgreSQL không chỉ là "MySQL phiên bản nâng cao". Nó là một hệ thống quản trị cơ sở dữ liệu quan hệ-đối tượng (Object-Relational DBMS) với triết lý thiết kế khác biệt: **ưu tiên tính đúng đắn (correctness) trước tốc độ (speed)**. MVCC nghiêm ngặt, type system phong phú (JSONB, ARRAY, ENUM, Range, hstore, ...), GIN/GiST index, và Partial Index là những vũ khí mà khi bạn thành thạo, sẽ giúp bạn nổi bật trong mắt nhà tuyển dụng.
>
> Nhớ: **Interviewer không tìm người thuộc lòng syntax. Họ tìm người hiểu TẠI SAO chọn giải pháp này thay vì giải pháp kia.**
>
> Chúc bạn phỏng vấn thành công! 🚀
