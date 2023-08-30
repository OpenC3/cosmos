/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
*/

/*
# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

#include "ruby.h"
#include "stdio.h"
#include "math.h"

VALUE mOpenC3;
VALUE cMicroservice;
VALUE cReducerMicroservice;

static ID id_method_raw_values = 0;
static ID id_method_converted_values = 0;
static ID id_method_less_than = 0;
static ID id_method_greater_than = 0;

static int reducer_microservice_update_min_stats_raw_value(VALUE key, VALUE value, VALUE reduced)
{
  volatile VALUE vals_key = Qnil;
  volatile VALUE n_key = Qnil;
  volatile VALUE x_key = Qnil;
  volatile VALUE reduced_entry = Qnil;

  if (RTEST(value))
  {
    vals_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(vals_key, rb_str_new2("__VALS"));
    reduced_entry = rb_hash_aref(reduced, vals_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = rb_ary_new();
      rb_hash_aset(reduced, vals_key, reduced_entry);
    }
    rb_ary_push(reduced_entry, value);

    n_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(n_key, rb_str_new2("__N"));
    reduced_entry = rb_hash_aref(reduced, n_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = value;
      rb_hash_aset(reduced, n_key, value);
    }
    if (RTEST(rb_funcall(value, id_method_less_than, 1, reduced_entry)))
    {
      rb_hash_aset(reduced, n_key, value);
    }

    x_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(x_key, rb_str_new2("__X"));
    reduced_entry = rb_hash_aref(reduced, x_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = value;
      rb_hash_aset(reduced, x_key, value);
    }
    if (RTEST(rb_funcall(value, id_method_greater_than, 1, reduced_entry)))
    {
      rb_hash_aset(reduced, x_key, value);
    }
  }

  return ST_CONTINUE;
}

static int reducer_microservice_update_min_stats_converted_value(VALUE key, VALUE value, VALUE reduced)
{
  volatile VALUE cvals_key = Qnil;
  volatile VALUE cn_key = Qnil;
  volatile VALUE cx_key = Qnil;
  volatile VALUE reduced_entry = Qnil;

  if (RTEST(value))
  {
    cvals_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(cvals_key, rb_str_new2("__CVALS"));
    reduced_entry = rb_hash_aref(reduced, cvals_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = rb_ary_new();
      rb_hash_aset(reduced, cvals_key, reduced_entry);
    }
    rb_ary_push(reduced_entry, value);

    cn_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(cn_key, rb_str_new2("__CN"));
    reduced_entry = rb_hash_aref(reduced, cn_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = value;
      rb_hash_aset(reduced, cn_key, value);
    }
    if (RTEST(rb_funcall(value, id_method_less_than, 1, reduced_entry)))
    {
      rb_hash_aset(reduced, cn_key, value);
    }

    cx_key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
    rb_str_append(cx_key, rb_str_new2("__CX"));
    reduced_entry = rb_hash_aref(reduced, cx_key);
    if (!(RTEST(reduced_entry)))
    {
      reduced_entry = value;
      rb_hash_aset(reduced, cx_key, value);
    }
    if (RTEST(rb_funcall(value, id_method_greater_than, 1, reduced_entry)))
    {
      rb_hash_aset(reduced, cx_key, value);
    }
  }

  return ST_CONTINUE;
}

static VALUE reducer_microservice_update_min_stats(VALUE self, VALUE reduced, VALUE state)
{
  volatile VALUE raw_values = rb_funcall(state, id_method_raw_values, 0);
  volatile VALUE converted_values = rb_funcall(state, id_method_converted_values, 0);

  /* Update statistics for this packet's raw values */
  rb_hash_foreach(raw_values, reducer_microservice_update_min_stats_raw_value, reduced);

  /* Update statistics for this packet's converted values */
  rb_hash_foreach(converted_values, reducer_microservice_update_min_stats_converted_value, reduced);

  return Qnil;
}

/*
 * Initialize methods for ReducerMicroservice
 */
void Init_reducer_microservice(void)
{
  id_method_raw_values = rb_intern("raw_values");
  id_method_converted_values = rb_intern("converted_values");
  id_method_less_than = rb_intern("<");
  id_method_greater_than = rb_intern(">");

  mOpenC3 = rb_define_module("OpenC3");
  rb_require("openc3/conversions/conversion");
  cMicroservice = rb_const_get(mOpenC3, rb_intern("Microservice"));
  cReducerMicroservice = rb_define_class_under(mOpenC3, "ReducerMicroservice", cMicroservice);
  rb_define_method(cReducerMicroservice, "update_min_stats", reducer_microservice_update_min_stats, 2);
}
