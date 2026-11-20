//
//  carchive.c
//  Bandizip for Mac
//

#include "carchive.h"

#include <archive.h>
#include <archive_entry.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define BZ_PATH_MAX 8192
#define BZ_DEST_MAX 16384
#define BZ_IO_BLOCK 262144
#define BZ_ERR_MAX 1024

struct bz_reader {
    char *path;
    char *password;
    struct archive *a;
    int64_t total_size;
    int total_known;
    char error[BZ_ERR_MAX];
};

struct bz_writer {
    struct archive *a;
    char *path;
    char error[BZ_ERR_MAX];
};

/* ------------------------------------------------------------------ */
/* 小工具                                                              */
/* ------------------------------------------------------------------ */

void bz_free(void *ptr)
{
    free(ptr);
}

static void copy_err(char *dst, size_t sz, const char *msg)
{
    if (!dst || sz == 0) {
        return;
    }
    if (!msg || !*msg) {
        msg = "未知错误";
    }
    snprintf(dst, sz, "%s", msg);
}

static void set_out_err(char **err, const char *msg)
{
    if (!err) {
        return;
    }
    if (*err) {
        free(*err);
        *err = NULL;
    }
    *err = strdup((msg && *msg) ? msg : "未知错误");
}

/* 递归创建目录，path 为绝对路径 */
static int ensure_dir(const char *path)
{
    char buf[BZ_DEST_MAX];
    size_t len;

    if (!path || !*path) {
        return 0;
    }
    len = strlen(path);
    if (len >= sizeof(buf)) {
        return -1;
    }
    memcpy(buf, path, len + 1);

    for (size_t i = 1; i < len; i++) {
        if (buf[i] == '/') {
            buf[i] = '\0';
            if (mkdir(buf, 0755) != 0 && errno != EEXIST) {
                buf[i] = '/';
                return -1;
            }
            buf[i] = '/';
        }
    }
    if (mkdir(buf, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

static void parent_dir(const char *path, char *out, size_t outsz)
{
    size_t len;
    if (!path || !out || outsz == 0) {
        return;
    }
    snprintf(out, outsz, "%s", path);
    len = strlen(out);
    while (len > 0 && out[len - 1] != '/') {
        len--;
    }
    if (len > 0) {
        out[len - 1] = '\0';
    }
    if (out[0] == '\0') {
        snprintf(out, outsz, "/");
    }
}

/* 去掉绝对路径 / 空段 / "." / ".."，结果使用 '/' 分隔 */
static void sanitize_path(const char *in, char *out, size_t outsz)
{
    size_t oi = 0;
    const char *p;

    if (!out || outsz == 0) {
        return;
    }
    out[0] = '\0';
    if (!in) {
        return;
    }

    p = in;
    while (*p) {
        const char *start;
        size_t seglen;

        while (*p == '/' || *p == '\\') {
            p++;
        }
        if (!*p) {
            break;
        }
        start = p;
        while (*p && *p != '/' && *p != '\\') {
            p++;
        }
        seglen = (size_t)(p - start);
        if (seglen == 0) {
            continue;
        }
        if (seglen == 1 && start[0] == '.') {
            continue;
        }
        if (seglen == 2 && start[0] == '.' && start[1] == '.') {
            continue;
        }
        if (oi + seglen + 2 >= outsz) {
            break;
        }
        if (oi > 0) {
            out[oi++] = '/';
        }
        memcpy(out + oi, start, seglen);
        oi += seglen;
    }
    out[oi] = '\0';
}

/* "a/b/report.txt" -> "a/b/report (1).txt" */
static void make_unique_path(const char *path, char *out, size_t outsz)
{
    const char *slash = strrchr(path, '/');
    const char *base = slash ? slash + 1 : path;
    const char *dot = strrchr(base, '.');
    const char *ext = "";
    size_t stem_len;

    if (dot && dot != base) {
        stem_len = (size_t)(dot - path);
        ext = dot;
    } else {
        stem_len = strlen(path);
    }

    for (int i = 1; i < 10000; i++) {
        char candidate[BZ_DEST_MAX];
        struct stat st;
        int n = snprintf(candidate, sizeof(candidate), "%.*s (%d)%s",
                         (int)stem_len, path, i, ext);
        if (n <= 0) {
            break;
        }
        if (lstat(candidate, &st) != 0) {
            snprintf(out, outsz, "%s", candidate);
            return;
        }
    }
    snprintf(out, outsz, "%s (copy)", path);
}

static void remove_existing(const char *path)
{
    struct stat st;
    if (lstat(path, &st) != 0) {
        return;
    }
    if (S_ISDIR(st.st_mode)) {
        rmdir(path);
    } else {
        unlink(path);
    }
}

static int is_wanted(const char *rel,
                     char (*only)[BZ_PATH_MAX],
                     int count)
{
    if (!only || count <= 0) {
        return 1;
    }
    for (int i = 0; i < count; i++) {
        const char *p = only[i];
        size_t n;
        if (!p || !*p) {
            continue;
        }
        if (strcmp(rel, p) == 0) {
            return 1;
        }
        n = strlen(p);
        if (strncmp(rel, p, n) == 0 && rel[n] == '/') {
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* 读取                                                                */
/* ------------------------------------------------------------------ */

bz_reader *bz_reader_open(const char *path, const char *password, char **err)
{
    struct bz_reader *r;
    struct archive *a;

    if (!path || !*path) {
        set_out_err(err, "压缩包路径为空");
        return NULL;
    }

    r = (struct bz_reader *)calloc(1, sizeof(*r));
    if (!r) {
        set_out_err(err, "内存不足");
        return NULL;
    }
    r->path = strdup(path);
    r->password = (password && *password) ? strdup(password) : NULL;
    r->total_size = 0;
    r->total_known = 1;

    a = archive_read_new();
    if (!a) {
        set_out_err(err, "无法初始化 libarchive");
        free(r->path);
        free(r->password);
        free(r);
        return NULL;
    }

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    if (r->password) {
        archive_read_add_passphrase(a, r->password);
    }

    if (archive_read_open_filename(a, path, BZ_IO_BLOCK) != ARCHIVE_OK) {
        const char *m = archive_error_string(a);
        set_out_err(err, m ? m : "无法打开压缩包");
        archive_read_free(a);
        free(r->path);
        free(r->password);
        free(r);
        return NULL;
    }

    r->a = a;
    return r;
}

void bz_reader_close(bz_reader *reader)
{
    if (!reader) {
        return;
    }
    if (reader->a) {
        archive_read_close(reader->a);
        archive_read_free(reader->a);
    }
    free(reader->path);
    free(reader->password);
    free(reader);
}

const char *bz_reader_error(bz_reader *reader)
{
    if (!reader || !reader->error[0]) {
        return NULL;
    }
    return reader->error;
}

int bz_reader_next(bz_reader *reader, bz_entry_info *out)
{
    struct archive_entry *entry = NULL;
    int rc = ARCHIVE_OK;
    const char *name;

    if (!reader || !reader->a || !out) {
        return -1;
    }

    for (;;) {
        rc = archive_read_next_header(reader->a, &entry);
        if (rc == ARCHIVE_RETRY) {
            continue;
        }
        if (rc == ARCHIVE_EOF) {
            return 0;
        }
        if (rc < ARCHIVE_WARN) {
            const char *m = archive_error_string(reader->a);
            copy_err(reader->error, BZ_ERR_MAX, m ? m : "读取压缩包失败");
            return -1;
        }
        break;
    }

    name = archive_entry_pathname_utf8(entry);
    if (!name || !*name) {
        name = archive_entry_pathname(entry);
    }
    if (!name) {
        name = "";
    }

    memset(out, 0, sizeof(*out));
    out->path = name;
    out->size = archive_entry_size_is_set(entry)
                    ? (int64_t)archive_entry_size(entry)
                    : -1;
    out->compressed_size = -1;
    out->mtime = (int64_t)archive_entry_mtime(entry);
    out->mode = (uint32_t)archive_entry_mode(entry);
    out->is_dir = (archive_entry_filetype(entry) == AE_IFDIR) ? 1 : 0;
    out->is_encrypted = (archive_entry_is_encrypted(entry) == 1) ? 1 : 0;

    if (out->size < 0) {
        reader->total_known = 0;
    } else {
        reader->total_size += out->size;
    }
    return 1;
}

int64_t bz_reader_total_size(bz_reader *reader)
{
    if (!reader || !reader->total_known) {
        return -1;
    }
    return reader->total_size;
}

int bz_reader_has_encrypted(bz_reader *reader)
{
    if (!reader || !reader->a) {
        return -1;
    }
    return archive_read_has_encrypted_entries(reader->a);
}

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
                      char **err)
{
    struct archive *a = NULL;
    struct archive *disk = NULL;
    struct archive_entry *entry = NULL;
    char (*only)[BZ_PATH_MAX] = NULL;
    char relpath[BZ_PATH_MAX];
    char destpath[BZ_DEST_MAX];
    char scratch[BZ_DEST_MAX];
    char resolved[BZ_DEST_MAX];
    const char *base = NULL;
    int64_t done = 0;
    int status = 0;
    int opts;

    if (!reader || !dest_dir || !*dest_dir) {
        set_out_err(err, "参数无效");
        return -1;
    }
    if (ensure_dir(dest_dir) != 0) {
        set_out_err(err, "无法创建目标文件夹");
        return -1;
    }

    /*
     * ARCHIVE_EXTRACT_SECURE_SYMLINKS 会拒绝穿过符号链接写文件，而 macOS 上
     * /tmp、/var 等都是符号链接（/tmp -> /private/tmp）。所以先把目标目录
     * 解析成真实路径，再拼接条目路径。
     */
    if (realpath(dest_dir, resolved) != NULL) {
        base = resolved;
    } else {
        base = dest_dir;
    }

    if (only_paths && only_count > 0) {
        only = (char (*)[BZ_PATH_MAX])calloc((size_t)only_count, BZ_PATH_MAX);
        if (!only) {
            set_out_err(err, "内存不足");
            return -1;
        }
        for (int i = 0; i < only_count; i++) {
            sanitize_path(only_paths[i] ? only_paths[i] : "", only[i], BZ_PATH_MAX);
        }
    }

    a = archive_read_new();
    if (!a) {
        set_out_err(err, "无法初始化 libarchive");
        free(only);
        return -1;
    }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    if (reader->password) {
        archive_read_add_passphrase(a, reader->password);
    }
    if (archive_read_open_filename(a, reader->path, BZ_IO_BLOCK) != ARCHIVE_OK) {
        const char *m = archive_error_string(a);
        set_out_err(err, m ? m : "无法打开压缩包");
        archive_read_free(a);
        free(only);
        return -1;
    }

    disk = archive_write_disk_new();
    if (!disk) {
        set_out_err(err, "无法初始化磁盘写入");
        archive_read_close(a);
        archive_read_free(a);
        free(only);
        return -1;
    }
    opts = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL |
           ARCHIVE_EXTRACT_FFLAGS | ARCHIVE_EXTRACT_SECURE_SYMLINKS |
           ARCHIVE_EXTRACT_SECURE_NODOTDOT;
    archive_write_disk_set_options(disk, opts);
    archive_write_disk_set_standard_lookup(disk);

    while (status == 0) {
        int rc;
        const char *name;
        int filetype;
        int is_dir;
        int wh;

        if (cancelled && cancelled(ctx)) {
            status = -3;
            break;
        }

        rc = archive_read_next_header(a, &entry);
        if (rc == ARCHIVE_EOF) {
            break;
        }
        if (rc == ARCHIVE_RETRY) {
            continue;
        }
        if (rc < ARCHIVE_WARN) {
            const char *m = archive_error_string(a);
            set_out_err(err, m ? m : "解压失败");
            status = -1;
            break;
        }

        name = archive_entry_pathname_utf8(entry);
        if (!name || !*name) {
            name = archive_entry_pathname(entry);
        }
        if (!name) {
            archive_read_data_skip(a);
            continue;
        }

        sanitize_path(name, relpath, sizeof(relpath));
        if (relpath[0] == '\0') {
            archive_read_data_skip(a);
            continue;
        }
        if (!is_wanted(relpath, only, only_count)) {
            archive_read_data_skip(a);
            continue;
        }

        snprintf(destpath, sizeof(destpath), "%s/%s", base, relpath);
        filetype = archive_entry_filetype(entry);
        is_dir = (filetype == AE_IFDIR);

        if (is_dir) {
            ensure_dir(destpath);
        } else {
            struct stat st;
            if (lstat(destpath, &st) == 0) {
                int act = policy;
                if (policy == 3) {
                    act = on_exists ? on_exists(destpath, ctx) : 1;
                }
                if (act == 0) {
                    archive_read_data_skip(a);
                    continue;
                }
                if (act == 2) {
                    make_unique_path(destpath, scratch, sizeof(scratch));
                    snprintf(destpath, sizeof(destpath), "%s", scratch);
                } else {
                    remove_existing(destpath);
                }
            }
            parent_dir(destpath, scratch, sizeof(scratch));
            ensure_dir(scratch);
        }

        archive_entry_set_pathname(entry, destpath);
        wh = archive_write_header(disk, entry);
        if (wh < ARCHIVE_WARN) {
            const char *m = archive_error_string(disk);
            set_out_err(err, m ? m : "写入文件失败");
            status = -1;
            break;
        }

        if (archive_entry_size(entry) != 0) {
            const void *buff = NULL;
            size_t size = 0;
            la_int64_t offset = 0;

            for (;;) {
                int br = archive_read_data_block(a, &buff, &size, &offset);
                if (br == ARCHIVE_EOF) {
                    break;
                }
                if (br < ARCHIVE_WARN) {
                    const char *m = archive_error_string(a);
                    set_out_err(err, m ? m : "读取数据失败");
                    status = -1;
                    break;
                }
                if (size > 0) {
                    if (archive_write_data_block(disk, buff, size, offset) < ARCHIVE_WARN) {
                        const char *m = archive_error_string(disk);
                        set_out_err(err, m ? m : "写入数据失败");
                        status = -1;
                        break;
                    }
                    done += (int64_t)size;
                    if (progress) {
                        progress(done, total_hint, ctx);
                    }
                }
                if (cancelled && cancelled(ctx)) {
                    status = -3;
                    break;
                }
            }
            if (status != 0) {
                break;
            }
        }

        archive_write_finish_entry(disk);
    }

    archive_write_close(disk);
    archive_write_free(disk);
    archive_read_close(a);
    archive_read_free(a);
    free(only);

    if (status == 0 && progress) {
        progress(total_hint > 0 ? total_hint : done,
                 total_hint > 0 ? total_hint : done, ctx);
    }
    return status;
}

/* ------------------------------------------------------------------ */
/* 写入                                                                */
/* ------------------------------------------------------------------ */

static int writer_configure(struct archive *a, const char *format, int level,
                            const char *password, char *ebuf, size_t esz)
{
    char opt[128];

    if (strcmp(format, "zip") == 0) {
        if (archive_write_set_format_zip(a) != ARCHIVE_OK) {
            copy_err(ebuf, esz, "当前系统不支持 ZIP 写入");
            return -1;
        }
        archive_write_set_options(a, "zip:compression=deflate");
        if (level > 0) {
            snprintf(opt, sizeof(opt), "zip:compression-level=%d", level);
            archive_write_set_options(a, opt);
        }
        if (password && *password) {
            archive_write_set_passphrase(a, password);
            archive_write_set_options(a, "zip:encryption=zipcrypt");
        }
        return 0;
    }

    if (strcmp(format, "7z") == 0) {
        if (archive_write_set_format_7zip(a) != ARCHIVE_OK) {
            copy_err(ebuf, esz, "当前系统不支持 7Z 写入");
            return -1;
        }
        archive_write_set_options(a, "7zip:compression=lzma2");
        if (level > 0) {
            snprintf(opt, sizeof(opt), "7zip:compression-level=%d", level);
            archive_write_set_options(a, opt);
        }
        if (password && *password) {
            archive_write_set_passphrase(a, password);
        }
        return 0;
    }

    if (archive_write_set_format_pax_restricted(a) != ARCHIVE_OK) {
        copy_err(ebuf, esz, "当前系统不支持 TAR 写入");
        return -1;
    }

    if (strcmp(format, "tar") == 0) {
        return 0;
    }
    if (strcmp(format, "tar.gz") == 0) {
        if (archive_write_add_filter_gzip(a) != ARCHIVE_OK) {
            copy_err(ebuf, esz, "当前系统不支持 gzip 压缩");
            return -1;
        }
        if (level > 0) {
            snprintf(opt, sizeof(opt), "gzip:compression-level=%d", level);
            archive_write_set_options(a, opt);
        }
        return 0;
    }
    if (strcmp(format, "tar.bz2") == 0) {
        if (archive_write_add_filter_bzip2(a) != ARCHIVE_OK) {
            copy_err(ebuf, esz, "当前系统不支持 bzip2 压缩");
            return -1;
        }
        if (level > 0) {
            snprintf(opt, sizeof(opt), "bzip2:compression-level=%d", level);
            archive_write_set_options(a, opt);
        }
        return 0;
    }
    if (strcmp(format, "tar.xz") == 0) {
        if (archive_write_add_filter_xz(a) != ARCHIVE_OK) {
            copy_err(ebuf, esz, "当前系统不支持 xz 压缩");
            return -1;
        }
        if (level > 0) {
            snprintf(opt, sizeof(opt), "xz:compression-level=%d", level);
            archive_write_set_options(a, opt);
        }
        return 0;
    }

    copy_err(ebuf, esz, "不支持的压缩格式");
    return -1;
}

int bz_format_supported(const char *format)
{
    struct archive *a;
    char ebuf[BZ_ERR_MAX];
    int rc;

    if (!format || !*format) {
        return 0;
    }
    a = archive_write_new();
    if (!a) {
        return 0;
    }
    ebuf[0] = '\0';
    rc = writer_configure(a, format, 5, NULL, ebuf, sizeof(ebuf));
    archive_write_free(a);
    return rc == 0 ? 1 : 0;
}

bz_writer *bz_writer_open(const char *path, const char *format, int level,
                          const char *password, char **err)
{
    struct bz_writer *w;
    char ebuf[BZ_ERR_MAX];

    if (!path || !*path || !format) {
        set_out_err(err, "参数无效");
        return NULL;
    }

    w = (struct bz_writer *)calloc(1, sizeof(*w));
    if (!w) {
        set_out_err(err, "内存不足");
        return NULL;
    }
    w->path = strdup(path);
    w->a = archive_write_new();
    if (!w->a) {
        set_out_err(err, "无法初始化 libarchive");
        free(w->path);
        free(w);
        return NULL;
    }

    ebuf[0] = '\0';
    if (writer_configure(w->a, format, level, password, ebuf, sizeof(ebuf)) != 0) {
        set_out_err(err, ebuf[0] ? ebuf : "无法配置压缩格式");
        archive_write_free(w->a);
        free(w->path);
        free(w);
        return NULL;
    }

    if (archive_write_open_filename(w->a, path) != ARCHIVE_OK) {
        const char *m = archive_error_string(w->a);
        set_out_err(err, m ? m : "无法创建压缩包");
        archive_write_free(w->a);
        free(w->path);
        free(w);
        return NULL;
    }

    return w;
}

static int add_header(struct bz_writer *w, const char *entry_name, int filetype,
                      const struct stat *st, const char *symlink_target)
{
    struct archive_entry *e = archive_entry_new();
    char name[BZ_PATH_MAX];
    int rc;

    if (!e) {
        return -1;
    }

    if (filetype == AE_IFDIR) {
        snprintf(name, sizeof(name), "%s/", entry_name);
    } else {
        snprintf(name, sizeof(name), "%s", entry_name);
    }

    archive_entry_set_pathname(e, name);
    archive_entry_set_filetype(e, filetype);
    archive_entry_set_perm(e, st->st_mode & 07777);
    archive_entry_set_mtime(e, st->st_mtimespec.tv_sec, st->st_mtimespec.tv_nsec);

    if (filetype == AE_IFREG) {
        archive_entry_set_size(e, st->st_size);
    } else {
        archive_entry_set_size(e, 0);
    }
    if (filetype == AE_IFLNK && symlink_target) {
        archive_entry_set_symlink(e, symlink_target);
    }

    rc = archive_write_header(w->a, e);
    archive_entry_free(e);
    if (rc < ARCHIVE_WARN) {
        const char *m = archive_error_string(w->a);
        copy_err(w->error, BZ_ERR_MAX, m ? m : "写入条目失败");
        return -1;
    }
    return 0;
}

static int add_regular_file(struct bz_writer *w, const char *fs_path,
                            const char *entry_name, const struct stat *st,
                            bz_progress_fn progress, bz_cancel_fn cancelled,
                            void *ctx, int64_t *done)
{
    char buf[BZ_IO_BLOCK];
    int fd;
    int status = 0;
    ssize_t n;

    if (add_header(w, entry_name, AE_IFREG, st, NULL) != 0) {
        return -1;
    }

    fd = open(fs_path, O_RDONLY);
    if (fd < 0) {
        copy_err(w->error, BZ_ERR_MAX, "无法读取文件");
        return -1;
    }

    for (;;) {
        if (cancelled && cancelled(ctx)) {
            status = -3;
            break;
        }
        n = read(fd, buf, sizeof(buf));
        if (n == 0) {
            break;
        }
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            copy_err(w->error, BZ_ERR_MAX, "读取文件失败");
            status = -1;
            break;
        }
        if (archive_write_data(w->a, buf, (size_t)n) < 0) {
            const char *m = archive_error_string(w->a);
            copy_err(w->error, BZ_ERR_MAX, m ? m : "写入数据失败");
            status = -1;
            break;
        }
        *done += (int64_t)n;
        if (progress) {
            progress(*done, -1, ctx);
        }
    }

    close(fd);
    if (status == 0) {
        archive_write_finish_entry(w->a);
    }
    return status;
}

static int add_path_recursive(struct bz_writer *w, const char *fs_path,
                              const char *entry_name,
                              bz_progress_fn progress, bz_cancel_fn cancelled,
                              void *ctx, int64_t *done);

static int add_directory(struct bz_writer *w, const char *fs_path,
                         const char *entry_name, const struct stat *st,
                         bz_progress_fn progress, bz_cancel_fn cancelled,
                         void *ctx, int64_t *done)
{
    struct dirent **namelist = NULL;
    int n;
    int status = 0;

    if (add_header(w, entry_name, AE_IFDIR, st, NULL) != 0) {
        return -1;
    }
    archive_write_finish_entry(w->a);

    n = scandir(fs_path, &namelist, NULL, alphasort);
    if (n < 0) {
        copy_err(w->error, BZ_ERR_MAX, "无法读取目录");
        return -1;
    }

    for (int i = 0; i < n; i++) {
        const char *name = namelist[i]->d_name;
        char child_path[BZ_PATH_MAX];
        char child_name[BZ_PATH_MAX];

        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
            strcmp(name, ".DS_Store") == 0) {
            free(namelist[i]);
            continue;
        }
        if (cancelled && cancelled(ctx)) {
            free(namelist[i]);
            status = -3;
            break;
        }

        snprintf(child_path, sizeof(child_path), "%s/%s", fs_path, name);
        snprintf(child_name, sizeof(child_name), "%s/%s", entry_name, name);

        status = add_path_recursive(w, child_path, child_name,
                                    progress, cancelled, ctx, done);
        free(namelist[i]);
        if (status != 0) {
            break;
        }
    }

    free(namelist);
    return status;
}

static int add_path_recursive(struct bz_writer *w, const char *fs_path,
                              const char *entry_name,
                              bz_progress_fn progress, bz_cancel_fn cancelled,
                              void *ctx, int64_t *done)
{
    struct stat st;

    if (lstat(fs_path, &st) != 0) {
        copy_err(w->error, BZ_ERR_MAX, "无法读取文件信息");
        return -1;
    }
    if (cancelled && cancelled(ctx)) {
        return -3;
    }

    if (S_ISDIR(st.st_mode)) {
        return add_directory(w, fs_path, entry_name, &st, progress, cancelled, ctx, done);
    }
    if (S_ISLNK(st.st_mode)) {
        char target[BZ_PATH_MAX];
        ssize_t n = readlink(fs_path, target, sizeof(target) - 1);
        if (n < 0) {
            copy_err(w->error, BZ_ERR_MAX, "无法读取符号链接");
            return -1;
        }
        target[n] = '\0';
        if (add_header(w, entry_name, AE_IFLNK, &st, target) != 0) {
            return -1;
        }
        archive_write_finish_entry(w->a);
        return 0;
    }
    if (S_ISREG(st.st_mode)) {
        return add_regular_file(w, fs_path, entry_name, &st, progress, cancelled, ctx, done);
    }
    return 0; /* 跳过 socket / fifo / 设备文件 */
}

int bz_writer_add(bz_writer *writer, const char *fs_path, const char *entry_name,
                  bz_progress_fn progress, bz_cancel_fn cancelled, void *ctx,
                  char **err)
{
    int64_t done = 0;
    int rc;

    if (!writer || !fs_path || !*fs_path || !entry_name || !*entry_name) {
        set_out_err(err, "参数无效");
        return -1;
    }

    writer->error[0] = '\0';
    rc = add_path_recursive(writer, fs_path, entry_name, progress, cancelled, ctx, &done);
    if (rc == -1) {
        set_out_err(err, writer->error[0] ? writer->error : "写入压缩包失败");
    }
    return rc;
}

int bz_writer_close(bz_writer *writer, char **err)
{
    int rc;

    if (!writer) {
        return -1;
    }

    rc = archive_write_close(writer->a);
    if (rc != ARCHIVE_OK) {
        const char *m = archive_error_string(writer->a);
        set_out_err(err, m ? m : "关闭压缩包失败");
    }
    archive_write_free(writer->a);

    if (rc != ARCHIVE_OK && writer->path) {
        unlink(writer->path);
    }
    free(writer->path);
    free(writer);
    return rc == ARCHIVE_OK ? 0 : -1;
}

void bz_writer_abort(bz_writer *writer)
{
    if (!writer) {
        return;
    }
    archive_write_close(writer->a);
    archive_write_free(writer->a);
    if (writer->path) {
        unlink(writer->path);
    }
    free(writer->path);
    free(writer);
}
