require 'rspec'
require_relative 'your_file_name' # Replace with the actual file name containing the OperatorProcessIO class

=begin
This test suite covers the following scenarios for both `extract()` and `finalize()` methods:

1. Handling fewer lines than `max_start_lines`
2. Handling more lines than `max_start_lines`
3. Truncating end lines when exceeding `max_end_lines`
4. Returning the correct output format
5. Clearing the file after extraction
6. Closing and unlinking the file after finalization

Make sure to replace `'your_file_name'` with the actual file name containing the `OperatorProcessIO` class. Also, ensure that you have RSpec installed (`gem install rspec`) before running these tests.

To run the tests, save this file with a `.rb` extension (e.g., `operator_process_io_spec.rb`) and execute it using the `rspec` command:

```
rspec operator_process_io_spec.rb
```

This test suite should provide good coverage for the `extract()` and `finalize()` methods of the `OperatorProcessIO` class.
=end

RSpec.describe OpenC3::OperatorProcessIO do
  let(:label) { 'test-io' }
  let(:max_start_lines) { 5 }
  let(:max_end_lines) { 3 }
  let(:io) { OpenC3::OperatorProcessIO.new(label, max_start_lines: max_start_lines, max_end_lines: max_end_lines) }

  describe '#extract' do
    context 'when there are fewer lines than max_start_lines' do
      it 'stores all lines in start_lines' do
        io.write("line1\nline2\nline3\n")
        io.extract
        expect(io.instance_variable_get(:@start_lines)).to eq(['line1', 'line2', 'line3'])
        expect(io.instance_variable_get(:@end_lines)).to be_empty
      end
    end

    context 'when there are more lines than max_start_lines' do
      it 'stores max_start_lines in start_lines and the rest in end_lines' do
        io.write("line1\nline2\nline3\nline4\nline5\nline6\nline7\n")
        io.extract
        expect(io.instance_variable_get(:@start_lines)).to eq(['line1', 'line2', 'line3', 'line4', 'line5'])
        expect(io.instance_variable_get(:@end_lines)).to eq(['line6', 'line7'])
      end
    end

    context 'when there are more end lines than max_end_lines' do
      it 'truncates end_lines to max_end_lines' do
        io.write("line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\n")
        io.extract
        expect(io.instance_variable_get(:@start_lines)).to eq(['line1', 'line2', 'line3', 'line4', 'line5'])
        expect(io.instance_variable_get(:@end_lines)).to eq(['line7', 'line8', 'line9'])
      end
    end

    it 'returns the extracted data' do
      data = "line1\nline2\nline3\n"
      io.write(data)
      expect(io.extract).to eq(data)
    end

    it 'clears the file after extraction' do
      io.write("line1\nline2\nline3\n")
      io.extract
      io.rewind
      expect(io.read).to be_empty
    end
  end

  describe '#finalize' do
    context 'when there are only start lines' do
      it 'returns only start lines' do
        io.write("line1\nline2\nline3\n")
        expect(io.finalize).to eq("line1\nline2\nline3\n")
      end
    end

    context 'when there are start and end lines' do
      it 'returns start lines, ..., and end lines' do
        io.write("line1\nline2\nline3\nline4\nline5\nline6\nline7\n")
        expect(io.finalize).to eq("line1\nline2\nline3\nline4\nline5\n...\nline6\nline7\n")
      end
    end

    context 'when there are more end lines than max_end_lines' do
      it 'truncates end lines' do
        io.write("line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\n")
        expect(io.finalize).to eq("line1\nline2\nline3\nline4\nline5\n...\nline7\nline8\nline9\n")
      end
    end

    it 'closes and unlinks the file' do
      expect(io).to receive(:close)
      expect(io).to receive(:unlink)
      io.finalize
    end
  end
end
