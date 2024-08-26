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

VALUE mOpenC3;
VALUE cConfigParser;

static ID id_cvar_progress_callback = 0;
static ID id_ivar_line_number = 0;
static ID id_ivar_keyword = 0;
static ID id_ivar_parameters = 0;
static ID id_ivar_line = 0;
static ID id_method_readline = 0;
static ID id_method_close = 0;
static ID id_method_pos = 0;
static ID id_method_call = 0;
static ID id_method_scan = 0;
static ID id_method_strip = 0;
static ID id_method_to_s = 0;
static ID id_method_upcase = 0;
static ID id_method_parse_errors = 0;

/*
 * Removes quotes from the given string if present.
 *
 *   "'quoted string'".remove_quotes #=> "quoted string"
 */
static VALUE string_remove_quotes(VALUE self)
{
  long length = RSTRING_LEN(self);
  char *ptr = RSTRING_PTR(self);
  char first_char = 0;
  char last_char = 0;

  if (length < 2)
  {
    return self;
  }

  first_char = ptr[0];
  if ((first_char != 34) && (first_char != 39))
  {
    return self;
  }

  last_char = ptr[length - 1];
  if (last_char != first_char)
  {
    return self;
  }

  return rb_str_new(ptr + 1, length - 2);
}

/*
 * Method to read a line from the config file.
 * This is a separate method so that it can be protected.
 */
static VALUE config_parser_readline(VALUE io)
{
  return rb_funcall(io, id_method_readline, 0);
}

/*
 * Iterates over each line of the io object and yields the keyword and parameters
 */
static VALUE parse_loop(VALUE self, VALUE io, VALUE yield_non_keyword_lines, VALUE remove_quotes, VALUE size, VALUE rx)
{
  int line_number = 0;
  int result = 0;
  long length = 0;
  int index = 0;
  double float_size = NUM2DBL(size);
  volatile VALUE progress_callback = rb_cvar_get(cConfigParser, id_cvar_progress_callback);
  volatile VALUE line = Qnil;
  volatile VALUE data = Qnil;
  volatile VALUE string_concat = Qfalse;
  volatile VALUE string = Qnil;
  volatile VALUE array = rb_ary_new();
  volatile VALUE first_item = Qnil;
  volatile VALUE ivar_keyword = Qnil;
  volatile VALUE ivar_parameters = rb_ary_new();
  volatile VALUE ivar_line = rb_str_new2("");
  volatile VALUE errors = rb_ary_new();

  rb_ivar_set(self, id_ivar_line_number, INT2FIX(0));
  rb_ivar_set(self, id_ivar_keyword, ivar_keyword);
  rb_ivar_set(self, id_ivar_parameters, ivar_parameters);
  rb_ivar_set(self, id_ivar_line, ivar_line);

  while (1)
  {
    line_number += 1;
    rb_ivar_set(self, id_ivar_line_number, INT2FIX(line_number));

    if (RTEST(progress_callback) && ((line_number % 10) == 0))
    {
      if (float_size > 0.0)
      {
        double float_pos = NUM2DBL(rb_funcall(io, id_method_pos, 0));
        rb_funcall(progress_callback, id_method_call, 1, rb_float_new(float_pos / float_size));
      }
    }

    line = rb_protect(config_parser_readline, io, &result);
    if (result)
    {
      rb_set_errinfo(Qnil);
      break;
    }
    line = rb_funcall(line, id_method_strip, 0);
    // Ensure the line length is not 0
    if (RSTRING_LEN(line) == 0) {
      continue;
    }

    if (RTEST(string_concat))
    {
      /* Skip comment lines after a string concat */
      if (RSTRING_PTR(line)[0] == '#')
      {
        continue;
      }
      /* Remove the opening quote if we're continuing the line */
      line = rb_str_new(RSTRING_PTR(line) + 1, RSTRING_LEN(line) - 1);
    }

    /* Check for string continuation */
    if ((RSTRING_PTR(line)[RSTRING_LEN(line) - 1] == '+') ||
        (RSTRING_PTR(line)[RSTRING_LEN(line) - 1] == '\\'))
    {
      int newline = 0;
      if (RSTRING_PTR(line)[RSTRING_LEN(line) - 1] == '+')
      {
        newline = 1;
      }
      rb_str_resize(line, RSTRING_LEN(line) - 1);
      line = rb_funcall(line, id_method_strip, 0);
      rb_str_append(ivar_line, line);
      rb_str_resize(ivar_line, RSTRING_LEN(ivar_line) - 1);
      if (newline == 1)
      {
        rb_str_cat2(ivar_line, "\n");
      }
      rb_ivar_set(self, id_ivar_line, ivar_line);
      string_concat = Qtrue;
      continue;
    }
    if (RSTRING_PTR(line)[RSTRING_LEN(line) - 1] == '&')
    {
      rb_str_append(ivar_line, line);
      rb_str_resize(ivar_line, RSTRING_LEN(ivar_line) - 1);
      rb_ivar_set(self, id_ivar_line, ivar_line);
      continue;
    }
    rb_str_append(ivar_line, line);
    rb_ivar_set(self, id_ivar_line, ivar_line);
    string_concat = Qfalse;

    data = rb_funcall(ivar_line, id_method_scan, 1, rx);
    first_item = rb_str_new2("");
    if (RARRAY_LEN(data) > 0)
    {
      rb_str_cat2(first_item, RSTRING_PTR(rb_ary_entry(data, 0)));
    }

    if ((RSTRING_LEN(first_item) == 0) || (RSTRING_PTR(first_item)[0] == '#'))
    {
      ivar_keyword = Qnil;
    }
    else
    {
      ivar_keyword = rb_funcall(first_item, id_method_upcase, 0);
    }
    rb_ivar_set(self, id_ivar_keyword, ivar_keyword);
    ivar_parameters = rb_ary_new();
    rb_ivar_set(self, id_ivar_parameters, ivar_parameters);

    /* Ignore lines without keywords: comments and blank lines */
    if (ivar_keyword == Qnil)
    {
      if (RTEST(yield_non_keyword_lines))
      {
        rb_ary_clear(array);
        rb_ary_push(array, ivar_keyword);
        rb_ary_push(array, ivar_parameters);
        line = rb_protect(rb_yield, array, &result);
        if (result)
        {
          rb_ary_push(errors, rb_errinfo());
          rb_set_errinfo(Qnil);
        }
      }
      ivar_line = rb_str_new2("");
      rb_ivar_set(self, id_ivar_line, ivar_line);
      continue;
    }

    length = RARRAY_LEN(data);
    if (length > 1)
    {
      for (index = 1; index < length; index++)
      {
        string = rb_ary_entry(data, index);

        /*
         * Don't process trailing comments such as:
         * KEYWORD PARAM #This is a comment
         * But still process Ruby string interpolations such as:
         * KEYWORD PARAM #{var}
         */
        if ((RSTRING_LEN(string) > 0) && (RSTRING_PTR(string)[0] == '#'))
        {
          if (!((RSTRING_LEN(string) > 1) && (RSTRING_PTR(string)[1] == '{')))
          {
            break;
          }
        }

        if (RTEST(remove_quotes))
        {
          rb_ary_push(ivar_parameters, string_remove_quotes(string));
        }
        else
        {
          rb_ary_push(ivar_parameters, string);
        }
      }
    }

    rb_ary_clear(array);
    rb_ary_push(array, ivar_keyword);
    rb_ary_push(array, ivar_parameters);
    line = rb_protect(rb_yield, array, &result);
    if (result)
    {
      rb_ary_push(errors, rb_errinfo());
      rb_set_errinfo(Qnil);
    }
    ivar_line = rb_str_new2("");
    rb_ivar_set(self, id_ivar_line, ivar_line);
  }

  rb_funcall(self, id_method_parse_errors, 1, errors);

  if (RTEST(progress_callback))
  {
    rb_funcall(progress_callback, id_method_call, 1, rb_float_new(1.0));
  }

  return Qnil;
}

/*
 * Initialize methods for ConfigParser
 */
void Init_config_parser(void)
{
  id_cvar_progress_callback = rb_intern("@@progress_callback");
  id_ivar_line_number = rb_intern("@line_number");
  id_ivar_keyword = rb_intern("@keyword");
  id_ivar_parameters = rb_intern("@parameters");
  id_ivar_line = rb_intern("@line");
  id_method_readline = rb_intern("readline");
  id_method_close = rb_intern("close");
  id_method_pos = rb_intern("pos");
  id_method_call = rb_intern("call");
  id_method_scan = rb_intern("scan");
  id_method_strip = rb_intern("strip");
  id_method_to_s = rb_intern("to_s");
  id_method_upcase = rb_intern("upcase");
  id_method_parse_errors = rb_intern("parse_errors");

  mOpenC3 = rb_define_module("OpenC3");

  cConfigParser = rb_define_class_under(mOpenC3, "ConfigParser", rb_cObject);
  rb_define_method(cConfigParser, "parse_loop", parse_loop, 5);
}
