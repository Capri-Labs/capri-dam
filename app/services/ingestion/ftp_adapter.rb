require 'net/ftp'
require 'tmpdir'

module IngestionAdapters
  # FTP / SFTP Adapter
  # For legacy on-premises DAMs or simple file server migrations.
  #
  # Credentials: host, port (default 21), username, password, remote_path (default '/')
  # Set auth_token = 'sftp' to use SFTP mode (requires net-sftp gem).
  class FtpAdapter < Base
    PAGE_SIZE = 200

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      files_list = []

      ftp_client do |ftp|
        remote_dir = credentials['remote_path'].presence || '/'
        ftp.chdir(remote_dir)

        all_files = ftp.list('*').map do |entry|
          # Parse FTP LIST output: "-rw-rw-r-- 1 user grp 5120 Jun 01 12:00 filename.jpg"
          parts = entry.split
          next if entry.start_with?('d')  # skip directories
          {
            identifier:    File.join(remote_dir, parts.last),
            size:          parts[4].to_i,
            original_name: parts.last,
            metadata: { 'modified' => "#{parts[5]} #{parts[6]} #{parts[7]}", 'source' => 'ftp' }
          }
        end.compact

        # Cursor-based pagination using array index
        offset     = cursor.to_i.zero? ? 0 : cursor.to_i
        files_list = all_files[offset, limit] || []

        return {
          files:       files_list,
          next_cursor: (offset + files_list.size).to_s,
          has_more:    (offset + files_list.size) < all_files.size
        }
      end
    end

    def download_and_stream(file_identifier, &block)
      tempfile = Tempfile.new(['ftp_migration_', File.extname(file_identifier)])
      tempfile.binmode

      ftp_client do |ftp|
        ftp.getbinaryfile(file_identifier, nil, 65_536) do |chunk|
          block.call(chunk) if block
          tempfile.write(chunk)
        end
      end

      tempfile.rewind
      tempfile.path
    ensure
      tempfile&.close
    end

    def test_connection
      ftp_client { |ftp| ftp.list }
      { success: true, message: "Connected to FTP server #{credentials['host']}." }
    rescue => e
      { success: false, message: "FTP connection failed: #{e.message}" }
    end

    private

    def ftp_client(&block)
      Net::FTP.open(
        credentials['host'],
        port:     (credentials['port'] || 21).to_i,
        username: credentials['username'],
        password: credentials['password'],
        passive:  true,
        ssl:      false
      ) do |ftp|
        block.call(ftp)
      end
    end
  end
end

