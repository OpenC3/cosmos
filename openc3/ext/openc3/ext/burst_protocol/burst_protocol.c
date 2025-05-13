/*
# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

#include "ruby.h"
#include "stdio.h"

static VALUE mOpenC3 = Qnil;
static VALUE cProtocol = Qnil;
static VALUE cBurstProtocol = Qnil;

static ID id_method_handle_sync_pattern = 0;
static ID id_method_reduce_to_single_packet = 0;
static ID id_method_replace = 0;
static ID id_method_clone = 0;
static ID id_method_log_discard = 0;

static ID id_ivar_data = 0;
static ID id_ivar_extra = 0;
static ID id_ivar_sync_pattern = 0;
static ID id_ivar_sync_state = 0;
static ID id_ivar_discard_leading_bytes = 0;

static VALUE symbol_RESYNC = Qnil;
static VALUE symbol_SEARCHING = Qnil;
static VALUE symbol_DISCONNECT = Qnil;
static VALUE symbol_STOP = Qnil;
static VALUE symbol_FOUND = Qnil;

/* Reads from the interface. It can look for a sync pattern before
 * creating a Packet. It can discard a set number of bytes at the beginning
 * before creating the Packet.
 *
 * Note: On the first call to this from any interface read(), data will contain a blank
 * string. Blank string is an opportunity for protocols to return any queued up packets.
 * If they have no queued up packets, they should pass the blank string down to chained
 * protocols giving them the same opportunity.
 *
 * @return [String|nil] Data for a packet consisting of the bytes read */
static VALUE burst_protocol_read_data(int argc, VALUE *argv, VALUE self)
{
  /* Arguments */
  volatile VALUE data = Qnil;
  volatile VALUE extra = Qnil;

  /* Internal variables */
  volatile VALUE result = Qnil;
  volatile VALUE control = Qnil;
  volatile VALUE packet_data = Qnil;
  volatile VALUE super_args[3] = {Qnil, Qnil, Qnil};

  long discard_leading_bytes = 0;

  switch (argc)
  {
  case 1:
    data = argv[0];
    break;
  case 2:
    data = argv[0];
    extra = argv[1];
    break;
  default:
    /* Invalid number of arguments given */
    rb_raise(rb_eArgError, "wrong number of arguments (%d for 1..2)", argc);
    break;
  };

  rb_str_concat(rb_ivar_get(self, id_ivar_data), data);

  /* Maintain extra from last read read_data */
  if (!((RSTRING_LEN(data) == 0) && (!(RTEST(extra))))) {
    rb_ivar_set(self, id_ivar_extra, extra);
  }

  while (1)
  {
    control = rb_funcall(self, id_method_handle_sync_pattern, 0);
    /* Only return here if not blank string test */
    if (RTEST(control) && (RSTRING_LEN(data) > 0))
    {
      return control;
    }

    /* Reduce the data to a single packet  */
    result = rb_funcall(self, id_method_reduce_to_single_packet, 0);
    if (RB_TYPE_P(result, T_ARRAY))
    {
      if (RARRAY_LEN(result) > 0)
      {
        packet_data = rb_ary_entry(result, 0);
        if (RARRAY_LEN(result) > 1)
        {
          extra = rb_ary_entry(result, 1);
        }
        else
        {
          extra = Qnil;
        }
      }
      else
      {
        packet_data = Qnil;
        extra = Qnil;
      }
    }
    else
    {
      packet_data = result;
      extra = Qnil;
    }
    if (packet_data == symbol_RESYNC)
    {
      rb_ivar_set(self, id_ivar_sync_state, symbol_SEARCHING);

      /* Only immediately resync if not blank string test */
      if (RSTRING_LEN(data) > 0)
      {
        continue;
      }
    }

    /* Potentially allow blank string to be sent to other protocols if no packet is ready in this one */
    if (SYMBOL_P(packet_data))
    {
      if ((RSTRING_LEN(data) <= 0) && (packet_data != symbol_DISCONNECT))
      {
        /* On blank string test, return blank string (unless we had a packet or need disconnect)
         * The base class handles the special case of returning STOP if on the last protocol in the
         * chain */
        super_args[0] = data;
        super_args[1] = extra;
        return rb_call_super(2, (VALUE *)super_args);
      }
      else
      {
        /* Return any control code if not on blank string test */
        result = rb_ary_new();
        rb_ary_push(result, packet_data);
        rb_ary_push(result, extra);
        return result;
      }
    }

    rb_ivar_set(self, id_ivar_sync_state, symbol_SEARCHING);

    /* Discard leading bytes if necessary */
    if (FIX2INT(rb_ivar_get(self, id_ivar_discard_leading_bytes)) > 0)
    {
      discard_leading_bytes = FIX2INT(rb_ivar_get(self, id_ivar_discard_leading_bytes));
      rb_str_replace(packet_data, rb_str_substr(packet_data, discard_leading_bytes, RSTRING_LEN(packet_data) - discard_leading_bytes));
    }

    result = rb_ary_new();
    rb_ary_push(result, packet_data);
    rb_ary_push(result, extra);
    return result;
  }
}

/* @return [Boolean] control code (nil, :STOP) */
static VALUE burst_protocol_handle_sync_pattern(VALUE self)
{
  volatile VALUE sync_pattern = rb_ivar_get(self, id_ivar_sync_pattern);
  volatile VALUE data = Qnil;
  long sync_index = -1;
  char *char_data = NULL;
  char *char_sync_pattern = NULL;
  long data_length = 0;
  long sync_pattern_length = 0;
  long i = 0;
  long index = 0;
  int found = 0;

  if (RTEST(sync_pattern) && (rb_ivar_get(self, id_ivar_sync_state) == symbol_SEARCHING))
  {
    data = rb_ivar_get(self, id_ivar_data);
    char_sync_pattern = RSTRING_PTR(sync_pattern);

    while (1)
    {
      data_length = RSTRING_LEN(data);
      sync_pattern_length = RSTRING_LEN(sync_pattern);

      /* Make sure we have some data to look for a sync word in */
      if (data_length < sync_pattern_length)
      {
        return symbol_STOP;
      }

      /* Find the beginning of the sync pattern */
      sync_index = -1;
      char_data = RSTRING_PTR(data);
      for (i = 0; i < data_length; i++)
      {
        if (char_data[i] == char_sync_pattern[0])
        {
          sync_index = i;
          break;
        }
      }

      if (sync_index != -1)
      {
        /* Make sure we have enough data for the whole sync pattern past this index */
        if (data_length < (sync_index + sync_pattern_length))
        {
          return symbol_STOP;
        }

        /* Check for the rest of the sync pattern */
        found = 1;
        index = sync_index;
        for (i = 0; i < sync_pattern_length; i++)
        {
          if (char_data[index] != char_sync_pattern[i])
          {
            found = 0;
            break;
          }
          index += 1;
        }

        if (found)
        {
          if (sync_index != 0)
          {
            rb_funcall(self, id_method_log_discard, 2, INT2FIX(sync_index), Qtrue);
            /* Delete Data Before Sync Pattern */
            rb_str_replace(data, rb_str_substr(data, sync_index, RSTRING_LEN(data) - sync_index));
          }
          rb_ivar_set(self, id_ivar_sync_state, symbol_FOUND);
          return Qnil;
        }
        else
        {
          rb_funcall(self, id_method_log_discard, 2, INT2FIX(sync_index + 1), Qfalse);
          /* Delete Data Before and including first character of suspected sync Pattern */
          rb_str_replace(data, rb_str_substr(data, sync_index + 1, RSTRING_LEN(data) - sync_index - 1));
          continue;
        } /* if found */
      }
      else
      {
        rb_funcall(self, id_method_log_discard, 2, INT2FIX(data_length), Qfalse);
        rb_str_replace(data, rb_str_new2(""));
        return symbol_STOP;
      }
    } /* end loop */
  }   /* if @sync_pattern */

  return Qnil;
}

static VALUE burst_protocol_reduce_to_single_packet(VALUE self)
{
  volatile VALUE result = Qnil;
  volatile VALUE packet_data = Qnil;
  volatile VALUE data = rb_ivar_get(self, id_ivar_data);

  if (RSTRING_LEN(data) <= 0)
  {
    /* Need some data */
    return symbol_STOP;
  }

  /* Reduce to packet data and clear data for next packet */
  packet_data = rb_funcall(data, id_method_clone, 0);
  rb_str_replace(data, rb_str_new2(""));

  result = rb_ary_new();
  rb_ary_push(result, packet_data);
  rb_ary_push(result, rb_ivar_get(self, id_ivar_extra));
  return result;
}

/*
 * Initialize all BurstProtocol methods
 */
void Init_burst_protocol(void)
{
  mOpenC3 = rb_define_module("OpenC3");

  symbol_RESYNC = ID2SYM(rb_intern("RESYNC"));
  symbol_SEARCHING = ID2SYM(rb_intern("SEARCHING"));
  symbol_DISCONNECT = ID2SYM(rb_intern("DISCONNECT"));
  symbol_STOP = ID2SYM(rb_intern("STOP"));
  symbol_FOUND = ID2SYM(rb_intern("FOUND"));

  id_method_handle_sync_pattern = rb_intern("handle_sync_pattern");
  id_method_reduce_to_single_packet = rb_intern("reduce_to_single_packet");
  id_method_replace = rb_intern("replace");
  id_method_clone = rb_intern("clone");
  id_method_log_discard = rb_intern("log_discard");

  id_ivar_data = rb_intern("@data");
  id_ivar_extra = rb_intern("@extra");
  id_ivar_sync_pattern = rb_intern("@sync_pattern");
  id_ivar_sync_state = rb_intern("@sync_state");
  id_ivar_discard_leading_bytes = rb_intern("@discard_leading_bytes");

  cProtocol = rb_define_class_under(mOpenC3, "Protocol", rb_cObject);
  cBurstProtocol = rb_define_class_under(mOpenC3, "BurstProtocol", cProtocol);
  rb_define_method(cBurstProtocol, "read_data", burst_protocol_read_data, -1);
  rb_define_method(cBurstProtocol, "reduce_to_single_packet", burst_protocol_reduce_to_single_packet, 0);
  rb_define_method(cBurstProtocol, "handle_sync_pattern", burst_protocol_handle_sync_pattern, 0);
}
