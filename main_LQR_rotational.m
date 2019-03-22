%% QUADROTOR BALANCING PENDULUM LQR SIMULATION - ROTATIONAL EQUILIBRIUM
%
% MATLAB simulation of the paper A Flying Inverted Pendulum by Markus Hehn 
% and Raffaello D'Andrea 
%
% Equilibrium point rotating around a constant radius at constant rot. vel

%% INIT
clc
clear
addpath('functions/');

%% DEFINE CONSTANTS
g = 9.81;       % m/s^2
m = 0.5;        % kg
L = 0.565;      % meters (Length of pendulum to center of mass)
l = 0.17;       % meters (Quadrotor center to rotor center)
I_yy = 3.2e-3;  % kg m^2 (Quadrotor inertia around y-axis)
I_xx = I_yy;    
I_zz = 5.5e-3;  % kg m^2 (Quadrotor inertia around z-axis)

simTime = 20;    % 8 second simulation
h = 0.05;       % sampling time
N = simTime/h;        

% define desired set point sequences in terms of Radius and Omega
R_radius_sequence = 2*ones(1,N+1); % + 0.5*sin(0.02*(1:N+1));   % meters (radius of turn)
Omega_sequence = 1*ones(1,N+1) + 0.0035*(1:N+1);      % rad/s (rotational velocity)
OmegaAngle_prev = 0;

%% INITIALIZE VARIABLE SEQUENCES

states_cart = zeros(3,N+1);
states_pendulum = zeros(2,N+1);
states_pendulum_actual = zeros(2,N+1);
euler_angles = zeros(2,N+1);
yaw_angle = zeros(1,N+1);

beta_angle = zeros(1,N+1);
gamma_angle = zeros(1,N+1);
beta_dot_angle = zeros(1,N+1);
gamma_dot_angle = zeros(1,N+1);

reference_trajectory = zeros(2,N+1);

u_tilde = zeros(1,N+1);
v_tilde = zeros(1,N+1);
w_tilde = zeros(1,N+1);

u_actual = zeros(1,N+1);

p_tilde = zeros(1,N+1);
q_tilde = zeros(1,N+1);

p_actual = zeros(1,N+1);
q_actual = zeros(1,N+1);

mu_tilde = zeros(1,N+1);
nu_tilde = zeros(1,N+1);

mu_actual = zeros(1,N+1);
nu_actual = zeros(1,N+1);

x = zeros(12,N+1); 
u = zeros(3, N+1);
y = zeros(12, N);
t = zeros(1,N+1);

% define initial conditions
%         p1  p2  q1 q2  u1 u2  v1 v2  w1 w2   mu   nu 
x(:,1) = [0.2  0  0  0   0  0   0  0   0  0   0.20  0.2 ]';

%% ITERATE THROUGH EACH TIME STEP

for k = 1:N
    t(:,k+1) = k*h;
    
    % Obtain new linearized system
    Omega = Omega_sequence(k);
    R_radius = R_radius_sequence(k);
    
    % get new linearized system matrices and Equilibrium nominal points
    [Ad,Bd,Cd,EP] = linearized_ss(L,g,Omega,R_radius,h);
    
    % Define Q and R and determine optimal LQR gain based on new system matrices
    R = 0.1*eye(3);                 
    Q = zeros(12,12); Q(5,5) = 1; Q(7,7) = 1; Q(9,9) = 1;   % only penalize position errors
    [~,eigvals,K] = dare(Ad,Bd,Q,R);
    
    % Determine control action from LQR   
    u(:,k) = -K*x(:,k);
    
    % Save variables
    u_tilde(k) = x(5,k);
    v_tilde(k) = x(7,k);
    w_tilde(k) = x(9,k);

    u_actual(k) = u_tilde(k) + EP.u_0;

    p_tilde(k) = x(1,k);
    q_tilde(k) = x(3,k);

    p_actual(k) = p_tilde(k) + EP.p_0;
    q_actual(k) = q_tilde(k) + EP.q_0;

    mu_tilde(k) = x(11,k);
    nu_tilde(k) = x(12,k);

    mu_actual(k) = mu_tilde(k) + EP.mu_0;
    nu_actual(k) = nu_tilde(k) + EP.nu_0;

    OmegaAngleT = OmegaAngle_prev + Omega*h;
    OmegaAngle_prev = OmegaAngleT;
    
    R_uvw_to_xyz = [cos(OmegaAngleT) -sin(OmegaAngleT) 0;
                    sin(OmegaAngleT)  cos(OmegaAngleT) 0;
                     0             0         1];
                 
    % determine x,y,z states of quadrotor
    states_cart(:,k) = R_uvw_to_xyz*[u_actual(k); v_tilde(k); w_tilde(k)];
    
    R_pq_to_rs = [cos(OmegaAngleT)  -sin(OmegaAngleT);
                  sin(OmegaAngleT)  cos(OmegaAngleT)];  
    R_euler = R_pq_to_rs;          
              
    % determine 
    euler_angles(:,k) = R_euler*[nu_actual(k); mu_actual(k)];
    
    yaw_angle(k) = 0;
              
    % determine r,s states of pendulum (relative to quadrotor center)
    states_pendulum(:,k) = R_pq_to_rs*[p_actual(k); q_actual(k)]; 
    
    % determine absolute pendulum position 
    states_pendulum_actual(:,k) = states_pendulum(:,k) + states_cart(1:2,k);
    
    % calculate control input in terms of omega_x,y,z
    mu = mu_actual(k);
    nu = nu_actual(k);
    
    % determine gamma, beta angles of quadrotor
    gamma = -asin(sin(OmegaAngleT)*sin(mu)*cos(nu) - cos(OmegaAngleT)*sin(nu));
    beta = asin((cos(OmegaAngleT)*sin(mu)*cos(nu) + sin(OmegaAngleT)*sin(nu))/(cos(gamma)));
    
    beta_angle(k) = beta;
    gamma_angle(k) = gamma;
    
    beta_dot_angle(k) = (R_radius*Omega^3*acos(gamma)*(tan(beta)*tan(gamma)*cos(OmegaAngleT) + acos(beta)*sin(OmegaAngleT)))/sqrt(g^2+(R_radius*Omega^2)^2);
    gamma_dot_angle(k) = (R_radius*Omega^3*acos(gamma)*cos(OmegaAngleT))/sqrt(g^2+(R_radius*Omega^2)^2);
    
    % determine reference input based on R_radius and Omega sequences
    reference_trajectory(:,k) = [cos(OmegaAngleT); sin(OmegaAngleT)]*R_radius;
    
    % Apply control and update state equations
    x(:,k+1) = Ad*x(:,k) + Bd*u(:,k);
    y(:,k) = Cd*x(:,k);
end

%% PLOT 3D TRAJECTORY

states_trajectory = [states_cart(1:3,:);
                     euler_angles(1,:);
                     euler_angles(2,:);   
                     yaw_angle;
                     states_pendulum(1:2,:)]';

visualize_quadrotor_trajectory_rotating(states_trajectory, reference_trajectory);
     
%% PLOT RESULTS

shouldplot = true;
if shouldplot
    % STATES 1-5
    figure(1);
    clf;
    sgtitle('Pendulum States');
    subplot 411;
    stairs(t, x(1,:), 'm-');  grid();
    ylabel('$p$ [m]','interpreter','latex');

    subplot 412;
    stairs(t, x(2,:), 'm-');  grid();
    ylabel('$\dot{p}$ [m/s]','interpreter','latex');

    subplot 413;
    stairs(t, x(3,:), 'b-');  grid();
    ylabel('$q$ [m]','interpreter','latex');

    subplot 414;
    stairs(t, x(4,:), 'b-');  grid();
    ylabel('$\dot{q}$ [m/s]','interpreter','latex');
    xlabel('Time [s]');

    % STATES 6-10
    figure(2);
    clf;
    sgtitle('Quadrotor States');
    subplot 611;
    stairs(t, x(5,:), 'm-');  grid();
    ylabel('$u$ [m]','interpreter','latex');

    subplot 612;
    stairs(t, x(6,:), 'm-');  grid();
    ylabel('$\dot{u}$ [m/s]','interpreter','latex');

    subplot 613;
    stairs(t, x(7,:), 'b-');  grid();
    ylabel('$v$ [m]','interpreter','latex');

    subplot 614;
    stairs(t, x(8,:), 'b-');  grid();
    ylabel('$\dot{v}$ [m/s]','interpreter','latex');

    subplot 615;
    stairs(t, x(9,:), 'k-');  grid();
    ylabel('$w$ [m]','interpreter','latex');

    subplot 616;
    stairs(t, x(10,:), 'k-');  grid();
    ylabel('$\dot{w}$ [m/s]','interpreter','latex');
    xlabel('Time [s]');
    
    % EULER ANGLES    
    figure(3);
    clf;
    sgtitle('Euler Angles');
    subplot 211;
    stairs(t, mu_actual, 'm-');  grid();
    ylabel('$\mu$','interpreter','latex');

    subplot 212;
    stairs(t, x(12,:), 'm-');  grid();
    ylabel('$\nu$','interpreter','latex');
    xlabel('Time [s]');

    % INPUTS
    figure(4);
    clf;
    sgtitle('Inputs');
    subplot 311;
    stairs(t, u(1,:), 'm-');  grid();
    ylabel('$\dot{\mu}$','interpreter','latex');

    subplot 312;
    stairs(t, u(2,:), 'm-');  grid();
    ylabel('$\dot{\nu}$','interpreter','latex');

    subplot 313;
    stairs(t, u(3,:), 'm-');  grid();
    ylabel('$a$','interpreter','latex');
    xlabel('Time [s]');
    
    % INPUTS FOR ROTOR THRUST
    figure(5);
    clf;
    stairs(t,beta_dot_angle);
    hold on
    stairs(t,gamma_dot_angle);
    legend('beta dot','gamma dot');
    title('Derivative of Control Inputs Seen By Quadrotor Props');
    grid();

    figure(6);
    clf;
    stairs(t,beta_angle);
    hold on
    stairs(t,gamma_angle);
    legend('beta','gamma');
    title('Control Inputs Seen By Quadrotor Props');
    grid();
end
    
%% FUNCTIONS
function Rt = R_x(y)
   Rt = [1   0      0    ;
         0 cos(y) -sin(y);
         0 sin(y)  cos(y)];
end

function Rt = R_y(y)
    Rt = [cos(y) 0  sin(y)    ;
            0    1    0;
         -sin(y) 0  cos(y)];
end
     
function Rt = R_z(y)
    Rt = [cos(y) -sin(y) 0;
          sin(y)  cos(y) 0;
            0       0    1];
end
     
function [Ad,Bd,Cd,EP] = linearized_ss(L,g,Omega,R_radius,h)

    % equilibrium constants
    q_0 = 0;
    zeta_0 = 0.5;   % initial zeta_0 estimate 
    % zeta_0 = sqrt(L^2-q_0^2-p_0^2); % zeta = relative position of pendulum along z-axis (Eqn 8)
    p_0 = -(Omega^2*R_radius)/(Omega^2+g/zeta_0);
    zeta_0 = sqrt(L^2-q_0^2-p_0^2); % correct

    z_0 = Inf; % NOT USED - constant reference altitude

    u_0 = R_radius;
    v_0 = 0;
    w_0 = 0;

    mu_0 = atan(-Omega^2*R_radius/g);        % nominal euler angle
    nu_0 = 0;                           % nominal euler angle
    a_0 = sqrt(g^2 + (R_radius*Omega^2)^2);    % nominal thrust

    C1 = zeta_0^2/L^2;
    C2 = Omega^2 + g*L^2/(zeta_0^3);
    C3 = Omega;
    C4 = -(p_0/zeta_0)*a_0*sin(mu_0) - a_0*cos(mu_0);
    C5 = (p_0/zeta_0)*cos(mu_0) - sin(mu_0);

    C6 = Omega^2 + g/zeta_0;

    %      p1  p2  q1  q2    u1  u2  v1   v2  w1  w2  mu            nu  
    Ac =[  0   1   0   0     0   0   0    0   0   0   0             0   ;  % p1
         C1*C2 0   0 2*C1*C3 0   0   0    0   0   0 C1*C4           0   ;  % p2
           0   0   0   1     0   0   0    0   0   0   0             0   ;  % q1
           0 -2*C3 C6  0     0   0   0    0   0   0   0            a_0  ;  % q2
           0   0   0   0     0   1   0    0   0   0   0             0   ;  % u1  
           0   0   0   0   C3^2  0   0   2*C3 0   0 a_0*cos(mu_0)   0   ;  % u2
           0   0   0   0     0   0   0    1   0   0   0             0   ;  % v1
           0   0   0   0     0 -2*C3 C3^2 0   0   0   0           -a_0  ;  % v2
           0   0   0   0     0   0   0    0   0   1   0             0   ;  % w1
           0   0   0   0     0   0   0    0   0   0 -a_0*sin(mu_0)  0   ;  % w2
           0   0   0   0     0   0   0    0   0   0   0             0   ;  % mu
           0   0   0   0     0   0   0    0   0   0   0             0   ]; % nu     

    %      mu_dot nu_dot a
    Bc =[  0      0      0;     % p1
           0      0    C1*C5;   % p2
           0      0      0;     % q1
           0      0      0;     % q2
           0      0      0;     % u1
           0      0  sin(mu_0); % u2
           0      0      0;     % v1
           0      0      0;     % v2
           0      0      0;     % w1
           0      0  cos(mu_0); % w2
           1      0      0;     % mu
           0      1      0 ];   % nu     
    
    % full state feedback
    Cc = eye(12);
    
    % descritize system
    sysc = ss(Ac,Bc,Cc,[]);
    
    sysd = c2d(sysc,h);

    Ad = sysd.A;
    Bd = sysd.B;
    Cd = sysd.C;
    
    % assign equilibrium parameters to struct
    EP.a_0 = a_0;
    EP.q_0 = q_0;
    EP.p_0 = p_0;
    EP.zeta_0 = zeta_0;
    
    EP.mu_0 = mu_0;
    EP.nu_0 = nu_0;
    
    EP.u_0 = u_0;
    EP.v_0 = v_0;
    EP.w_0 = w_0;
    
    EP.z_0 = z_0;
end
     
     
     
     
     
     
     
%.