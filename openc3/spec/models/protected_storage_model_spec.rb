# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/protected_storage_model'

module OpenC3
  describe ProtectedStorageModel do
    before(:each) { mock_redis() }

    describe '.add' do
      it 'stores root and prefix, normalizing the prefix to end with a slash' do
        ProtectedStorageModel.add(root: 'OPENC3_CONFIG_BUCKET', prefix: 'protected_dir')
        expect(Store.smembers(ProtectedStorageModel::KEY)).to eql(['OPENC3_CONFIG_BUCKET:protected_dir/'])
      end

      it 'keeps an existing trailing slash and an empty prefix' do
        ProtectedStorageModel.add(root: 'OPENC3_CONFIG_BUCKET', prefix: 'a/')
        ProtectedStorageModel.add(root: 'OPENC3_X_VOLUME')
        expect(Store.smembers(ProtectedStorageModel::KEY)).to match_array(['OPENC3_CONFIG_BUCKET:a/', 'OPENC3_X_VOLUME:'])
      end

      it 'is idempotent' do
        2.times { ProtectedStorageModel.add(root: 'OPENC3_CONFIG_BUCKET', prefix: 'a') }
        expect(Store.smembers(ProtectedStorageModel::KEY).length).to eql(1)
      end
    end

    describe '.protected?' do
      before(:each) { ProtectedStorageModel.add(root: 'OPENC3_CONFIG_BUCKET', prefix: 'protected_dir') }

      it 'protects keys under the prefix' do
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: 'protected_dir/shard0/x')).to be true
      end

      it 'protects the prefix directory itself' do
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: 'protected_dir')).to be true
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: 'protected_dir/')).to be true
      end

      it 'normalizes leading slashes, dot segments and doubled slashes' do
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: '/protected_dir/x')).to be true
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: './protected_dir//x')).to be true
      end

      it 'does not protect a sibling that shares the prefix text' do
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_CONFIG_BUCKET', key: 'protected_dir_other/x')).to be false
      end

      it 'does not protect other roots' do
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_LOGS_BUCKET', key: 'protected_dir/x')).to be false
      end

      it 'protects everything under the root when the prefix is empty' do
        ProtectedStorageModel.add(root: 'OPENC3_X_VOLUME')
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_X_VOLUME', key: 'anything/at/all')).to be true
        expect(ProtectedStorageModel.protected?(root: 'OPENC3_X_VOLUME', key: '')).to be true
      end
    end
  end
end
