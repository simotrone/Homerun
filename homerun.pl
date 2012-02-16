#!/usr/bin/env perl
use Mojolicious::Lite;
use Carp;
use IO::Dir;
use 5.010;


my $conf = plugin 'Config';
$ENV{MOJO_MAX_MESSAGE_SIZE} = $conf->{'upload_limit'};
app->secret($conf->{'secret'});

app->types->type(odt => 'application/vnd.oasis.opendocument.text'); # OpenDocument Text
app->types->type(odp => 'application/vnd.oasis.opendocument.presentation'); # OD Presentation
app->types->type(ods => 'application/vnd.oasis.opendocument.spreadsheet'); # OD Spreadsheet;

helper 'file_limit' => sub {
        my $l = shift->config('file_limit');
        return $l > 0 ? $l : 1;
};
helper 'storage_dir' => sub {
        my $self = shift;
        return join('/', $self->app->home, $self->config('storage_dir'));
};


helper 'byte_str' => sub {
        my ($self, $byte) = @_;

        my ($num,$um) = ($byte,'B');

        given ($byte) {
                when (1024 <= $_ && $_ < 1024*1024) {
                        $num = $byte/1024;
                        $um  = 'KB';
                }
                when ($_ >= 1024*1024) {
                        $num = $byte/1024/1024;
                        $um  = 'MB';
                }
        };

        return sprintf("%.2f %s",$num,$um);
};

# Remove files that exceed in 'storage/'
helper 'remover' => sub {
        my $self  = shift;
        
        my @files = $self->scanner;
        my $dir   = $self->storage_dir;
        my $limit = $self->file_limit;

        return unless (scalar(@files) > $limit);

        my @sliced = @files[$limit..$#files];
        foreach my $f (@sliced) {
                my $file = "$dir/$f";
                next unless (-f $file);
                if (unlink $file) {
                        $self->app->log->info("Removed file: $f");
                } else {
                        $self->app->log->info("Could not unlink $f: $!");
                }
        }
};

# Find files in 'storage/' and return ordered by ctime
helper 'scanner' => sub {
        my $self = shift;

        my $dir = $self->storage_dir;
        my $d = IO::Dir->new($dir);

        croak "No storage dir available." unless (defined $d);

        my @files = grep { !/^\./ && -f "$dir/$_" } $d->read;
        $d->close;

        # sorting on ctime
        my @sorted = sort {
                (stat("$dir/$b"))[10] <=> (stat("$dir/$a"))[10]
        } @files;

        return @sorted;
};

# Select right numbers of files in 'storage/'
helper 'chooser' => sub {
        my $self = shift;

        my @files = $self->scanner;
        return "No file in." if (scalar @files < 1);

        my $limit = $self->file_limit;

        my @sliced = @files;
        @sliced = @sliced[0..$limit-1] if (@sliced > $limit);

        return \@sliced;
};

helper 'last' => sub {
        my $files = shift->chooser;
        return $files unless (ref $files eq 'ARRAY');
        return $files->[0];
};

# Routes
get '/' => sub {
        my $self = shift;

        $self->stash('last' => $self->last);
        $self->render('index');
} => 'home';

get '/archive' => sub {
        my $self = shift;
        $self->stash('things' => $self->chooser);
};

get '/get/:file' => sub {
        my $self  = shift;

        my $file = $self->param('file');
        my $ext  = $self->stash('format');
        my $basename = $self->config('basename') || 'default';

        my $asset = Mojo::Asset::File->new->path(join('/', $self->storage_dir, "$file.$ext"));
        $self->app->log->debug('File '.$asset->path.' required.');

        return $self->flash('err_msg' => 'File is not deployable.')->redirect_to('home')
                unless (-r $asset->path);

        my $t = $self->app->types;
        my $ct = $t->type($ext) || $t->type('bin');

        my $res = $self->res;
        $res->content->asset($asset);
        $res->headers->content_type($ct);
        $res->headers->content_disposition(qq{attachment; filename="$basename.$ext"})
                if ($ext eq 'ods');
        $self->rendered(200);
} => 'get';

post '/upload' => sub {
        my $self = shift;

        # Check file size
        if ($self->req->is_limit_exceeded) {
                my $size_limit = $self->byte_str($self->config('upload_limit'));
                my $err_msg    = "File is too big [$size_limit limit]. No upload.";
                return $self->flash('err_msg' => $err_msg)->redirect_to('home');
        }

        # Process uploaded file
        if (my $f = $self->req->upload('file')) {
                # TODO check if no upload
                return $self->redirect_to('home') unless ($f->size > 0);

                my $name = $f->filename;
                $name =~ m/\.(\w+)$/;
                my $ext = $1;

                my ($ss,$mm,$hh,$d,$m,$y) = localtime(time);
                my $str = sprintf("%d%02d%02d",$y+1900,$m+1,$d) ."_" .sprintf("%02d%02d%02d",$hh,$mm,$ss) .".$ext";
                $f->move_to(join('/', $self->storage_dir, $str));
                $self->app->log->info($self->tx->remote_address ." upload file $str");

                # Remove exceeding files
                $self->remover;

                my $size_str = $self->byte_str($f->size);
                $self->flash('ok_msg' => "File $name [$size_str] uploaded.")->redirect_to('home');
        }

        return $self->redirect_to('home');
};

app->start;
