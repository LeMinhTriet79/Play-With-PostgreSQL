-- ============================================================
-- 🐘 E-LEARNING LAB SETUP — Chạy file này trên PostgreSQL
-- Tạo database trước: CREATE DATABASE elearning;
-- Rồi kết nối: \c elearning
-- ============================================================

-- Bước 0: Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Bước 1: Enum Types
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS enrollment_status CASCADE;
DROP TYPE IF EXISTS course_level CASCADE;

CREATE TYPE user_role AS ENUM ('STUDENT', 'TEACHER', 'ADMIN');
CREATE TYPE enrollment_status AS ENUM ('ACTIVE', 'COMPLETED', 'DROPPED');
CREATE TYPE course_level AS ENUM ('BEGINNER', 'INTERMEDIATE', 'ADVANCED');

-- Bước 2: Drop tables nếu tồn tại (để chạy lại được)
DROP TABLE IF EXISTS quiz_results CASCADE;
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS lessons CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Bước 3: Tạo bảng
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       VARCHAR(255) NOT NULL UNIQUE,
    full_name   VARCHAR(150) NOT NULL,
    role        user_role    NOT NULL DEFAULT 'STUDENT',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_role ON users(role);

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

CREATE TABLE lessons (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title       VARCHAR(300) NOT NULL,
    content     TEXT,
    metadata    JSONB NOT NULL DEFAULT '{}',
    tags        TEXT[] NOT NULL DEFAULT '{}',
    sort_order  INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_lessons_course ON lessons(course_id);

CREATE TABLE enrollments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id       UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    status          enrollment_status NOT NULL DEFAULT 'ACTIVE',
    enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    UNIQUE(student_id, course_id)
);
CREATE INDEX idx_enrollments_student ON enrollments(student_id);
CREATE INDEX idx_enrollments_course  ON enrollments(course_id);

CREATE TABLE quiz_results (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    score       NUMERIC(5, 2) NOT NULL CHECK (score >= 0 AND score <= 100),
    quiz_config JSONB NOT NULL DEFAULT '{}',
    taken_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_quiz_student ON quiz_results(student_id);
CREATE INDEX idx_quiz_course  ON quiz_results(course_id);

-- Bước 4: Insert dữ liệu mẫu
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

INSERT INTO lessons (id, course_id, title, content, metadata, tags, sort_order) VALUES
    ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
     'Giới thiệu Spring Boot', 'Nội dung bài giảng...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-01.mp4", "duration_minutes": 45, "attachments": [{"name": "slides.pdf", "size_mb": 2.5}]}',
     ARRAY['spring', 'java', 'beginner'], 1),
    ('d2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111',
     'Dependency Injection Deep Dive', 'Nội dung bài giảng DI...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-02.mp4", "duration_minutes": 60, "attachments": [{"name": "di-examples.zip", "size_mb": 5.0}]}',
     ARRAY['spring', 'DI', 'IoC', 'advanced'], 2),
    ('d3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111',
     'Spring Data JPA & Hibernate', 'Nội dung JPA...',
     '{"video_url": "https://cdn.edu.vn/videos/sb-03.mp4", "duration_minutes": 75, "attachments": []}',
     ARRAY['spring', 'JPA', 'hibernate', 'database'], 3),
    ('d4444444-4444-4444-4444-444444444444', 'c2222222-2222-2222-2222-222222222222',
     'JSONB & Indexing nâng cao', 'Nội dung JSONB...',
     '{"video_url": "https://cdn.edu.vn/videos/pg-01.mp4", "duration_minutes": 90, "attachments": [{"name": "jsonb-cheatsheet.pdf", "size_mb": 1.2}], "requires_lab": true}',
     ARRAY['postgresql', 'jsonb', 'indexing', 'performance'], 1),
    ('d5555555-5555-5555-5555-555555555555', 'c3333333-3333-3333-3333-333333333333',
     'Container Fundamentals', 'Nội dung Docker cơ bản...',
     '{"video_url": "https://cdn.edu.vn/videos/dk-01.mp4", "duration_minutes": 55, "attachments": [], "requires_lab": true}',
     ARRAY['docker', 'container', 'devops'], 1);

INSERT INTO enrollments (student_id, course_id, status, enrolled_at, completed_at) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 'COMPLETED', '2026-01-15 08:00:00+07', '2026-04-20 17:00:00+07'),
    ('b1111111-1111-1111-1111-111111111111', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE', '2026-05-01 09:00:00+07', NULL),
    ('b2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 'ACTIVE', '2026-03-10 10:30:00+07', NULL),
    ('b2222222-2222-2222-2222-222222222222', 'c3333333-3333-3333-3333-333333333333', 'ACTIVE', '2026-06-01 14:00:00+07', NULL),
    ('b3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111', 'COMPLETED', '2026-02-01 07:45:00+07', '2026-05-15 16:00:00+07'),
    ('b3333333-3333-3333-3333-333333333333', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE', '2026-06-15 08:00:00+07', NULL),
    ('b4444444-4444-4444-4444-444444444444', 'c1111111-1111-1111-1111-111111111111', 'DROPPED', '2026-01-20 11:00:00+07', NULL),
    ('b5555555-5555-5555-5555-555555555555', 'c2222222-2222-2222-2222-222222222222', 'ACTIVE', '2026-07-01 09:30:00+07', NULL),
    ('b6666666-6666-6666-6666-666666666666', 'c3333333-3333-3333-3333-333333333333', 'ACTIVE', '2026-08-01 13:00:00+07', NULL);

INSERT INTO quiz_results (student_id, course_id, score, quiz_config, taken_at) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 85.50,
     '{"total_questions": 20, "time_limit_minutes": 30, "passing_score": 60, "answers": [{"question_id": 1, "selected": "B", "correct": "B", "is_correct": true}, {"question_id": 2, "selected": "A", "correct": "C", "is_correct": false}, {"question_id": 3, "selected": "D", "correct": "D", "is_correct": true}], "submitted_from_ip": "192.168.1.100"}',
     '2026-04-18 15:30:00+07'),
    ('b2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 72.00,
     '{"total_questions": 20, "time_limit_minutes": 30, "passing_score": 60, "answers": [{"question_id": 1, "selected": "B", "correct": "B", "is_correct": true}, {"question_id": 2, "selected": "C", "correct": "C", "is_correct": true}], "submitted_from_ip": "10.0.0.55"}',
     '2026-06-20 10:00:00+07'),
    ('b3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111', 95.00,
     '{"total_questions": 20, "time_limit_minutes": 30, "passing_score": 60, "answers": [{"question_id": 1, "selected": "B", "correct": "B", "is_correct": true}, {"question_id": 2, "selected": "C", "correct": "C", "is_correct": true}, {"question_id": 3, "selected": "D", "correct": "D", "is_correct": true}], "submitted_from_ip": "172.16.0.12"}',
     '2026-05-10 09:00:00+07'),
    ('b1111111-1111-1111-1111-111111111111', 'c2222222-2222-2222-2222-222222222222', 68.00,
     '{"total_questions": 25, "time_limit_minutes": 45, "passing_score": 70, "answers": [{"question_id": 1, "selected": "A", "correct": "A", "is_correct": true}], "submitted_from_ip": "192.168.1.100"}',
     '2026-08-05 14:00:00+07'),
    ('b3333333-3333-3333-3333-333333333333', 'c2222222-2222-2222-2222-222222222222', 88.50,
     '{"total_questions": 25, "time_limit_minutes": 45, "passing_score": 70, "answers": [], "submitted_from_ip": "172.16.0.12"}',
     '2026-08-20 11:30:00+07'),
    ('b5555555-5555-5555-5555-555555555555', 'c2222222-2222-2222-2222-222222222222', 42.00,
     '{"total_questions": 25, "time_limit_minutes": 45, "passing_score": 70, "answers": [], "submitted_from_ip": "10.0.0.77"}',
     '2026-09-01 16:00:00+07'),
    ('b2222222-2222-2222-2222-222222222222', 'c3333333-3333-3333-3333-333333333333', 78.00,
     '{"total_questions": 15, "time_limit_minutes": 25, "passing_score": 65, "answers": [{"question_id": 1, "selected": "C", "correct": "C", "is_correct": true}], "submitted_from_ip": "10.0.0.55"}',
     '2026-09-10 10:00:00+07');

-- Bước 5: GIN Indexes cho JSONB & ARRAY
CREATE INDEX idx_quiz_config_gin ON quiz_results USING gin(quiz_config jsonb_path_ops);
CREATE INDEX idx_lessons_tags_gin ON lessons USING gin(tags);
CREATE INDEX idx_lessons_metadata_gin ON lessons USING gin(metadata);

-- Bước 6: Kiểm tra
SELECT 'users' AS tbl, COUNT(*) FROM users
UNION ALL SELECT 'courses', COUNT(*) FROM courses
UNION ALL SELECT 'lessons', COUNT(*) FROM lessons
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments
UNION ALL SELECT 'quiz_results', COUNT(*) FROM quiz_results;

-- ✅ Output kỳ vọng:
-- users: 9 | courses: 4 | lessons: 5 | enrollments: 9 | quiz_results: 7
