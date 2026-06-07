// SPDX-License-Identifier: GPL-2.0-only
/*
 * Device Mapper Proxy (dmp) - proxy target with statistic
 */

#include "dm.h"
#include <linux/atomic.h>
#include <linux/bio.h>
#include <linux/blkdev.h>
#include <linux/device-mapper.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/sysfs.h>

#define DM_MSG_PREFIX "dmp"

/* Structure for statistics */
struct dmp_stats
{
	atomic64_t read_reqs;
	atomic64_t read_bytes;
	atomic64_t write_reqs;
	atomic64_t write_bytes;
};

struct dmp_c
{
	struct dm_dev *dev;
	sector_t start;
	struct dmp_stats stats;
};

static struct dmp_stats global_stats;

/* kobject for sysfs: /sys/module/dmp/stat */
static struct kobject *dmp_kobj;

static ssize_t volumes_show(struct kobject *kobj,
							struct kobj_attribute *attr,
							char *buf)
{
	s64 r_reqs, r_bytes, w_reqs, w_bytes, t_reqs, t_bytes;
	s64 r_avg = 0, w_avg = 0, t_avg = 0;

	r_reqs = atomic64_read(&global_stats.read_reqs);
	r_bytes = atomic64_read(&global_stats.read_bytes);
	w_reqs = atomic64_read(&global_stats.write_reqs);
	w_bytes = atomic64_read(&global_stats.write_bytes);

	if (r_reqs > 0)
		r_avg = r_bytes / r_reqs;
	if (w_reqs > 0)
		w_avg = w_bytes / w_reqs;

	t_reqs = r_reqs + w_reqs;
	t_bytes = r_bytes + w_bytes;
	if (t_reqs > 0)
		t_avg = t_bytes / t_reqs;

	return sprintf(buf,
				   "read: reqs: %lld avg size: %lld\n"
				   "write: reqs: %lld avg size: %lld\n"
				   "total: reqs: %lld avg size: %lld\n",
				   (long long)r_reqs, (long long)r_avg,
				   (long long)w_reqs, (long long)w_avg,
				   (long long)t_reqs, (long long)t_avg);
}

static struct kobj_attribute volumes_attr =
	__ATTR(volumes, 0444, volumes_show, NULL);

static struct attribute *dmp_attrs[] = {
	&volumes_attr.attr,
	NULL,
};

static struct attribute_group dmp_attr_group = {
	.attrs = dmp_attrs,
};

static int dmp_ctr(struct dm_target *ti, unsigned int argc, char **argv)
{
	struct dmp_c *dmp;
	int ret;

	if (argc < 1 || argc > 2) {
		ti->error = "dmp: Invalid argument count. Usage: dmp <dev_path> [physical_offset]";
		return -EINVAL;
	}

	dmp = kzalloc(sizeof(*dmp), GFP_KERNEL);
	if (!dmp) {
		ti->error = "dmp: Memory allocation failed";
		return -ENOMEM;
	}

	ret = dm_get_device(ti, argv[0], dm_table_get_mode(ti->table), &dmp->dev);
	if (ret) {
		ti->error = "dmp: Device lookup failed";
		goto err_free;
	}

	if (argc == 2) {
		if (kstrtoull(argv[1], 10, (unsigned long long *)&dmp->start) != 0) {
			ti->error = "dmp: Invalid physical offset";
			goto err_bad;
		}
	} else {
		dmp->start = 0;
	}

	atomic64_set(&dmp->stats.read_reqs, 0);
	atomic64_set(&dmp->stats.read_bytes, 0);
	atomic64_set(&dmp->stats.write_reqs, 0);
	atomic64_set(&dmp->stats.write_bytes, 0);

	ti->private = dmp;

	ti->num_flush_bios = 1;
	ti->num_discard_bios = 1;
	ti->num_write_same_bios = 1;
	ti->num_write_zeroes_bios = 1;

	return 0;

err_bad:
	dm_put_device(ti, dmp->dev);
err_free:
	kfree(dmp);
	return ret;
}

static void dmp_dtr(struct dm_target *ti)
{
	struct dmp_c *dmp = ti->private;
	dm_put_device(ti, dmp->dev);
	kfree(dmp);
}

static sector_t dmp_map_sector(struct dm_target *ti, sector_t bi_sector)
{
	struct dmp_c *dmp = ti->private;
	return dmp->start + dm_target_offset(ti, bi_sector);
}

static int dmp_map(struct dm_target *ti, struct bio *bio)
{
	struct dmp_c *dmp = ti->private;
	bio_set_dev(bio, dmp->dev->bdev);
	
	bio->bi_iter.bi_sector = dmp->start + dm_target_offset(ti, bio->bi_iter.bi_sector);
	if (bio_data_dir(bio) == READ) {
		atomic64_inc(&global_stats.read_reqs);
		atomic64_add(bio->bi_iter.bi_size, &global_stats.read_bytes);
	} else {
		atomic64_inc(&global_stats.write_reqs);
		atomic64_add(bio->bi_iter.bi_size, &global_stats.write_bytes);
	}

	return DM_MAPIO_REMAPPED;
}

static void dmp_status(struct dm_target *ti, status_type_t type,
					   unsigned int status_flags, char *result, unsigned int maxlen)
{
	struct dmp_c *dmp = ti->private;
	switch (type) {
	case STATUSTYPE_INFO:
		result[0] = '\0';
		break;
	case STATUSTYPE_TABLE:
		if (dmp->start == 0) {
			snprintf(result, maxlen, "%s", dmp->dev->name);
		} else {
			snprintf(result, maxlen, "%s %llu", dmp->dev->name, (unsigned long long)dmp->start);
		}
		break;
	}
}

static int dmp_iterate_devices(struct dm_target *ti,
							   iterate_devices_callout_fn fn, void *data)
{
	struct dmp_c *dmp = ti->private;
	return fn(ti, dmp->dev, dmp->start, ti->len, data);
}

static struct target_type dmp_target = {
	.name = "dmp",
	.version = {1, 0, 0},
	.features = DM_TARGET_PASSES_INTEGRITY | DM_TARGET_NOWAIT,
	.module = THIS_MODULE,
	.ctr = dmp_ctr,
	.dtr = dmp_dtr,
	.map = dmp_map,
	.status = dmp_status,
	.iterate_devices = dmp_iterate_devices,
};

static int __init dmp_init(void)
{
	int r;
	r = dm_register_target(&dmp_target);
	if (r < 0) {
		DMERR("register failed %d", r);
		return r;
	}

	dmp_kobj = kobject_create_and_add("stat", &THIS_MODULE->mkobj.kobj);
	if (!dmp_kobj) {
		DMERR("Failed to create sysfs directory 'stat'");
		r = -ENOMEM;
		goto err_unregister_dm;
	}

	r = sysfs_create_group(dmp_kobj, &dmp_attr_group);
	if (r) {
		DMERR("Failed to create sysfs group");
		goto err_put_kobj;
	}

	atomic64_set(&global_stats.read_reqs, 0);
	atomic64_set(&global_stats.read_bytes, 0);
	atomic64_set(&global_stats.write_reqs, 0);
	atomic64_set(&global_stats.write_bytes, 0);

	pr_info("dmp: module loaded successfully\n");
	return 0;

err_put_kobj:
	kobject_put(dmp_kobj);
	dmp_kobj = NULL;
err_unregister_dm:
	dm_unregister_target(&dmp_target);
	return r;
}

static void __exit dmp_exit(void)
{
	if (dmp_kobj) {
		sysfs_remove_group(dmp_kobj, &dmp_attr_group);
		kobject_put(dmp_kobj);
		dmp_kobj = NULL;
	}

	dm_unregister_target(&dmp_target);
	pr_info("dmp: module unloaded\n");
}

module_init(dmp_init);
module_exit(dmp_exit);

MODULE_LICENSE("GPL");
MODULE_ALIAS("dm:dmp");
MODULE_DESCRIPTION("Device Mapper Proxy with I/O statistics");