# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates a 7z file using `vcpkg export` for use with Ruby mswin
# builds in GitHub Actions.

require 'fileutils'
require 'optparse'
require_relative 'common'

module CreateMswin
  class << self

    include Common

    PACKAGES = 'libffi libyaml openssl readline-win32 zlib'
    PKG_DEPENDS = 'vcpkg-cmake vcpkg-cmake-config vcpkg-cmake-get-vars'

    PKG_NAME = 'mswin'

    EXPORT_DIR = "#{TEMP}".gsub "\\", '/'

    VCPKG = ENV.fetch 'VCPKG_INSTALLATION_ROOT', 'C:/vcpkg'

    OPENSSL_PKG = 'packages/openssl_x64-windows'


    def get_triplet(static)
      static ? 'x64-windows-static' : 'x64-windows'
    end

    def copy_ssl_files(static)
      # Locations for vcpkg OpenSSL build
      # X509::DEFAULT_CERT_FILE      C:\vcpkg\packages\openssl_x64-windows/cert.pem
      # X509::DEFAULT_CERT_DIR       C:\vcpkg\packages\openssl_x64-windows/certs
      # Config::DEFAULT_CONFIG_FILE  C:\vcpkg\packages\openssl_x64-windows/openssl.cnf

      vcpkg_u = VCPKG.gsub "\\", '/'

      # make certs dir
      export_ssl_path = "#{EXPORT_DIR}/#{PKG_NAME}/#{OPENSSL_PKG}"
      FileUtils.mkdir_p "#{export_ssl_path}/certs"

      # updating OpenSSL package may overwrite cert.pem
      cert_path = "#{RbConfig::TOPDIR}/ssl/cert.pem"

      if File.readable? cert_path
        vcpkg_ssl_path = "#{vcpkg_u}/#{OPENSSL_PKG}"
        unless Dir.exist? vcpkg_ssl_path
          FileUtils.mkdir_p vcpkg_ssl_path
        end
        IO.copy_stream cert_path, "#{vcpkg_ssl_path}/cert.pem"
        IO.copy_stream cert_path, "#{export_ssl_path}/cert.pem"
      end

      # copy openssl.cnf file
      conf_path = "#{vcpkg_u}/installed/#{get_triplet(static)}/tools/openssl/openssl.cnf"
      if File.readable? conf_path
        IO.copy_stream conf_path, "#{export_ssl_path}/openssl.cnf"
      end
    end

    def generate_package_files(static)
      ENV['VCPKG_ROOT'] = VCPKG

      Dir.chdir VCPKG do |d|
        update_info = %x(./vcpkg update)
        if update_info.include?('No packages need updating') && !ENV.key?('FORCE_UPDATE')
          STDOUT.syswrite "\n#{GRN}No packages need updating#{RST}\n\n"
          exit 0
        else
          STDOUT.syswrite "\n#{YEL}#{LINE} Updates needed#{RST}\n#{update_info}"
        end

        exec_check "Upgrading #{PACKAGES}",
          "./vcpkg upgrade #{PACKAGES} #{PKG_DEPENDS} --triplet=#{get_triplet(static)} --no-dry-run"

        exec_check "Removing outdated packages",
          "./vcpkg remove --outdated"

        exec_check "Exporting package files from vcpkg",
          "./vcpkg export --triplet=#{get_triplet(static)} #{PACKAGES} --raw --output=#{PKG_NAME} --output-dir=#{EXPORT_DIR}"
      end

      # remove tracked files
      Dir.chdir "#{EXPORT_DIR}/#{PKG_NAME}" do
        FileUtils.remove_dir 'scripts', true
      end

      vcpkg_u = VCPKG.gsub "\\", '/'

      # vcpkg/installed/status contains a list of installed packages
      status_path = 'installed/vcpkg/status'
      IO.copy_stream "#{vcpkg_u}/#{status_path}", "#{EXPORT_DIR}/#{PKG_NAME}/#{status_path}"
    end

    def run(static)
      puts static
      generate_package_files(static)

      copy_ssl_files(static)

      suffix = static ? '-static' : ''
      pkg_name = "#{PKG_NAME}#{suffix}"

      # create 7z archive file
      tar_path = "#{__dir__}\\#{pkg_name}.7z".gsub '/', '\\'

      Dir.chdir("#{EXPORT_DIR}/#{pkg_name}") do
        exec_check "Creating 7z file", "\"#{SEVEN}\" a #{tar_path}"
      end

      time = Time.now.utc.strftime '%Y-%m-%d %H:%M:%S UTC'
      upload_7z_update pkg_name, time
    end
  end
end

static = false
OptionParser.new do |opts|
  opts.banner = "Usage: create_mswin_pkg.rb [options]"

  opts.on("-s", "--static", "Use static vcpkg libraries") { |v| static = true }
end.parse!

CreateMswin.run(static)
