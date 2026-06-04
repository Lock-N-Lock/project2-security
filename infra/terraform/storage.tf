# =============================================================
# storage.tf — S3 (DB pg_dump 백업)
# 구현방안1(Terraform 범위에 S3) + 구현방안3(pg_dump→S3) 반영
# 파일위치 : ~/project2-security/infra/terraform/storage.tf
# =============================================================

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "db_backup" {
  bucket = "${var.project}-db-backup-${data.aws_caller_identity.me.account_id}"
  tags   = { Name = "${var.project}-db-backup" }
}

resource "aws_s3_bucket_versioning" "db_backup" {
  bucket = aws_s3_bucket.db_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "db_backup" {
  bucket                  = aws_s3_bucket.db_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ======================================================================
# storage.tf 파일 내부의 수명주기 설정 블록 교체본 (예시)
# ======================================================================
resource "aws_s3_bucket_lifecycle_configuration" "db_backup_policy" {
  bucket = aws_s3_bucket.db_backup.id

  rule {
    id     = "db-backup-retention"
    status = "Enabled"

    # ◀ 이 자리에 빈 filter 블록을 추가하여 버킷 전체 적용임을 명시합니다.
    filter {}

    expiration {
      days = 7 # 데모/과제 요건에 맞게 일수 설정 (예: 7일 후 자동 삭제)
    }
  }
}