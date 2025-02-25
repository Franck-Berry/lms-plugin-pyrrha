package WebService::Pandora::Method;

use strict;
use warnings;

use WebService::Pandora::Cryptor;

use URI;
use JSON;
use Data::Dumper;

### constructor ###

sub new {

    my $caller = shift;

    my $class = ref( $caller );
    $class = $caller if ( !$class );

    my $self = {'name' => undef,
                'partnerAuthToken' => undef,
                'userAuthToken' => undef,
                'partnerId' => undef,
                'userId' => undef,
                'syncTime' => undef,
                'host' => undef,
                'ssl' => 0,
                'encrypt' => 1,
                'cryptor' => undef,
                'timeout' => 10,
                'params' => {},
                @_};

    bless( $self, $class );

    # create and store json object
    $self->{'json'} = JSON->new()->utf8;

    return $self;
}

### getters/setters ###

sub error {

    my ( $self, $error ) = @_;

    $self->{'error'} = $error if ( defined( $error ) );

    return $self->{'error'};
}

### public methods ###

sub execute {

    my ( $self, $cb ) = @_;

    # make sure both name and host were given
    if ( !defined( $self->{'name'} ) || !defined( $self->{'host'} ) ) {
        $self->error( 'Both the name and host must be provided to the constructor.' );
        $cb->(error => $self->error());
        return;
    }

    # craft the json data accordingly
    my $json_data = {};

    if ( defined( $self->{'userAuthToken'} ) ) {
        $json_data->{'userAuthToken'} = $self->{'userAuthToken'};
    }

    if ( defined( $self->{'syncTime'} ) ) {
        $json_data->{'syncTime'} = time() + $self->{'syncTime'};
    }

    # merge the two required params with the additional user-supplied args
    $json_data = {%$json_data, %{$self->{'params'}}};

    # encode it to json
    $json_data = $self->{'json'}->encode( $json_data );

    # encrypt it, if needed
    if ( $self->{'encrypt'} ) {
        $json_data = $self->{'cryptor'}->encrypt( $json_data );

        # detect error decrypting
        if ( !defined( $json_data ) ) {
            $self->error( 'An error occurred encrypting our JSON data: ' . $self->{'cryptor'}->error() );
            $cb->(error => $self->error());
            return;
        }
    }

    # http or https?
    my $protocol = ( $self->{'ssl'} ) ? 'https://' : 'http://';

    # craft the full URL, protocol + host + path
    my $url = $protocol . $self->{'host'} . '/services/json/';

    # create URI object
    my $uri = URI->new( $url );

    # create all url params for POST request
    my $url_params = ['method' => $self->{'name'}];

    # set user_auth_token if provided
    if ( defined( $self->{'userAuthToken'} ) ) {
        push( @$url_params, 'auth_token' => $self->{'userAuthToken'} );
    }

    # set partner_auth_token if provided and user_auth_token was not
    elsif ( defined( $self->{'partnerAuthToken'} ) ) {
        push( @$url_params, 'auth_token' => $self->{'partnerAuthToken'} );
    }

    # set partner_id if provided
    if ( defined( $self->{'partnerId'} ) ) {
        push( @$url_params, 'partner_id' => $self->{'partnerId'} );
    }

    # set user_id if provided
    if ( defined( $self->{'userId'} ) ) {
        push( @$url_params, 'user_id' => $self->{'userId'} );
    }

    # add the params to the URI
    $uri->query_form( $url_params );

    # create and store the POST request accordingly
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $response = shift;
            my $json_data = $self->{'json'}->decode( $response->content );

            # handle pandora error
            if ( $json_data->{'stat'} ne 'ok' ) {
                $self->error( {
                  'apiCode'    => $json_data->{'code'},
                  'apiMessage' => $json_data->{'message'},
                  'message'    => "$self->{'name'} error $json_data->{'code'}: $json_data->{'message'}",
                } );
                $cb->(error => $self->error());
            }
            else {
                my $result = defined($json_data->{'result'}) ? $json_data->{'result'} : 1;
                $cb->(result => $result);
            }
        },
        sub {
            my ($req, $error) = @_;
            $self->error( $error );
            $cb->(error => $self->error());
        },
        {
            timeout => $self->{timeout},
        }
    );
    $http->post($uri, $json_data);
}

1;
