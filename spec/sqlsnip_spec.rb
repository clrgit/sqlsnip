require 'tempfile'

describe "sqlsnip" do
  using String::Text

  let!(:file) { Tempfile.new('mock.source.sql').path }

  def sqlsnip(src, start: nil, stop: nil, search_path: "", interactive: false) 
    IO.write(file, src.align)
    src = Sqlsnip::Source.parse(file, start, stop, search_path: search_path)
    src.generate(interactive: interactive).join("\n")
  end

  it 'has a version number' do
    expect(Sqlsnip::VERSION).not_to be_nil
  end

  context 'generates drop statements for' do
    it 'tables' do
      src = %(
        create table t;
      )
      expect(sqlsnip src).to eq "drop table if exists t cascade;"
    end
  end

  context "when given a range of lines" do
    it "only generates drop statements for objects in the range" do
      src = %(
        create table line1;
        create table line2;
        create table line3;
        create table line4;
      )
      expect(sqlsnip src, start: 2, stop: 3).to eq %(
        drop table if exists line2 cascade;
        drop table if exists line3 cascade;
      ).align

      expect(sqlsnip src, start: 2).to eq %(
        drop table if exists line2 cascade;
        drop table if exists line3 cascade;
        drop table if exists line4 cascade;
      ).align
    end
  end

  context "when the search_path option" do
    context "is nil" do
      it "searches the file for an initial search path" do
        src = %(
          set search_path to target;
          set search_path to another_target;
          create table t;
        )
        expect(sqlsnip src, start: 2).to eq %(
          set search_path to another_target;
          drop table if exists t cascade;
        ).align
      end
      it "detects the search_path from the directory"
    end

    context "is the empty string" do
      it "does not set an initial search_path" do
        src = %(
          create table t;
        )
        expect(sqlsnip src).to eq "drop table if exists t cascade;"
      end
    end

    context "is a schema name" do
      it "uses it as the search path" do
        src = %(
          create table t;
        )
        expect(sqlsnip src, search_path: "public").to eq %(
          set search_path to public;
          drop table if exists t cascade;
        ).align
      end
    end
  end

  context "with the interactive option" do
    it "sets ON_ERROR_STOP" do
      src = %(
        create table t;
      )
      expect(sqlsnip src, interactive: true).to eq "\\set ON_ERROR_STOP on\ndrop table if exists t cascade;"
    end
  end
end
