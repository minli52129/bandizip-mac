//
//  carchive.h
//  Bandizip for Mac
//
//  libarchive 的极薄 C 桥接层。所有类型都用 void* / 基础类型暴露，
//  避免 Swift 侧对不完整结构体的导入差异。
//

#ifndef CARCHIVE_H
#define CARCHIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bz_reader bz_reader;
typedef struct bz_writer bz_writer;

typedef struct bz_entry_info {
    const char *path;        /* UTF-8，直到下一次 bz_reader_next 前有效 */
    int64_t size;            /* 原始大小，-1 表示未知 */
    int64_t compressed_size; /* 压缩后大小，-1 表示未知 */
    int64_t mtime;           /* Unix 时间戳（秒） */
    uint32_t mode;           /* 完整 st_mode */
    int32_t is_dir;
    int32_t is_encrypted;
} bz_entry_info;

/* 进度回调：done 已处理字节，total 预先估算的总字节（-1 未知） */
typedef void (*bz_progress_fn)(int64_t done, int64_t total, void *ctx);
/* 取消回调：返回 1 表示用户要求取消 */
typedef int (*bz_cancel_fn)(void *ctx);
/* 同名文件回调：0 跳过，1 覆盖，2 重命名 */
typedef int (*bz_exists_fn)(const char *path, void *ctx);

/* ---------- 读取 / 解压 ---------- */

bz_reader *bz_reader_open(const char *path, const char *password, char **err);
void bz_reader_close(bz_reader *reader);
const char *bz_reader_error(bz_reader *reader);
/* 1 = 成功读到一条，0 = 结束，-1 = 出错 */
int bz_reader_next(bz_reader *reader, bz_entry_info *out);
int64_t bz_reader_total_size(bz_reader *reader);
/* 1 = 含加密条目，0 = 未加密，-1 = 该格式不支持判断 */
int bz_reader_has_encrypted(bz_reader *reader);

/*
 * policy: 0 = 跳过同名，1 = 覆盖，2 = 自动重命名，3 = 逐项询问（调用 on_exists）
 * only_paths: 仅解压这些条目（NULL 表示全部），前缀匹配目录
 * 返回 0 成功，-1 失败，-3 已取消
 */
int bz_reader_extract(bz_reader *reader,
                      const char *dest_dir,
                      int policy,
                      int64_t total_hint,
                      const char *const *only_paths,
                      int only_count,
                      bz_progress_fn progress,
                      bz_exists_fn on_exists,
                      bz_cancel_fn cancelled,
                      void *ctx,
                      char **err);

void bz_free(void *ptr);

/* ---------- 创建 / 压缩 ---------- */

bz_writer *bz_writer_open(const char *path, const char *format, int level,
                          const char *password, char **err);
/* 返回 0 成功，-1 失败，-3 已取消 */
int bz_writer_add(bz_writer *writer, const char *fs_path, const char *entry_name,
                  bz_progress_fn progress, bz_cancel_fn cancelled, void *ctx,
                  char **err);
int bz_writer_close(bz_writer *writer, char **err);
void bz_writer_abort(bz_writer *writer);
/* 1 = 当前系统支持该格式，0 = 不支持 */
int bz_format_supported(const char *format);

#ifdef __cplusplus
}
#endif

#endif /* CARCHIVE_H */
