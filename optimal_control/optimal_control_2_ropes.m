clear all ; close all ; clc

%cd to actual dir if you are not already there
filePath = matlab.desktop.editor.getActiveFilename;
pathparts = strsplit(filePath,filesep);
dirpath= pathparts(1:end-1);
actual_dir =  strjoin(dirpath,"/");
cd(actual_dir);


USEGENCODE = false;
COPYTOLOCOSIM = false;

r_spool = 0.025
%possible settings
test_type='normal' ;
%test_type='obstacle_avoidance' ;
%test_type='landing_test'; 


if strcmp(test_type, 'obstacle_avoidance')
    %jump params
    % INITIAL POINT
    p0 = [0.5, 0.5, -6]; % there is singularity for px = 0!
    %FINAL TARGET
    pf= [0.5, 4.5, -6];
    %intermediate jump
    pf(2)= p0(2)+ (pf(2)-p0(2))/2;
    pf(1) = 1.5;

    Fleg_max = 300;
    Fr_max = 90; % Fr is negative

    % the order of params matters for code generation
    params.jump_clearance = 1; % ensure at least this detachment from wall
    params.m = 5.08;   % Mass [kg]
    params.obstacle_avoidance  = true;

elseif  strcmp(test_type, 'landing_test')
    %jump params
    % INITIAL POINT
    p0 = [0.5, 2.5, -6]; % there is singularity for px = 0!
    %FINAL TARGET
    pf= [0.5, 4,-4];
  
    Fleg_max = 600;
    Fr_max = 300;

    % the order of params matters for code generation
    params.jump_clearance = 1.; % ensure at least this detachment from wall
    params.m = 15.07; 
    params.obstacle_avoidance  = false;

else %normal
    %jump params
    % INITIAL POINT
    p0 = [0.5, 1, -10]; % there is singularity for px = 0!
    %FINAL TARGET
    pf= [0.5, 4,-2]
    Fleg_max = 300;
    Fr_max = 90; % Fr is negative

    % the order of params matters for code generation
    params.jump_clearance = 1; % ensure at least this detachment from wall
    params.m = 10.08;   % Mass [kg]
    params.obstacle_avoidance  = false;
end
 
params.obstacle_location = [-0.5; 2.5; -6];
params.obstacle_size = [1.5; 1.5; 0.866];

%WORLD FRAME ATTACHED TO ANCHOR 1
anchor_distance = 5;
params.num_params = 4;   
params.int_method = 'rk4';
params.N_dyn = 30; %dynamic constraints (number of knowts in the discretization) 
params.FRICTION_CONE = 1;
params.int_steps = 5.; %0 means normal intergation
params.contact_normal =[1;0;0];
params.b = anchor_distance;
params.p_a1 = [0;0;0];
params.p_a2 = [0;anchor_distance;0];
params.g = 9.81;
params.w1=1; % diff Fr1/2 smothing
params.w2=0; %hoist work
params.w3=0; %(not used)
params.w4=0;% %(not used)
params.w5=0; %  %(not used0 ekinf (important! energy has much higher values!)
params.w6=0;%  %(not used)
params.contact_normal =[1;0;0];
params.T_th =  0.05;

mu = 0.8;

%gen code (run if you did some change in the cost)
if ~isfile('optimize_cpp_mex.mexa64')
    disp('Generating C++ code');
    % generates the cpp code
    % run the mex generator after calling optimize_cpp otherwise he complains it is missing the pa1 
    cfg = coder.config('mex');
    cfg.IntegrityChecks = false;
    cfg.SaturateOnIntegerOverflow = false;
    codegen -config cfg  optimize_cpp -args {[0, 0, 0], [0, 0, 0], 0, 0, 0, coder.cstructname(params, 'param') } -nargout 1 -report
    if COPYTOLOCOSIM
        disp("copying to locosim")  
        copyfile codegen/mex/optimize_cpp/ ~/trento_lab_home/ros_ws/src/locosim/robot_control/base_controllers/climbingrobot_controller/codegen/mex/optimize_cpp
        copyfile optimize_cpp_mex.mexa64 ~/trento_lab_home/ros_ws/src/locosim/robot_control/base_controllers/climbingrobot_controller/codegen/
    end
end


mpc_fun   = 'optimize_cpp';
if USEGENCODE  
    mpc_fun=append(mpc_fun,'_mex' );
end
mpc_fun_handler = str2func(mpc_fun);
solution = mpc_fun_handler(p0,  pf, Fleg_max, Fr_max, mu, params);

switch solution.problem_solved
    case 1 
        fprintf(2,"Problem converged!\n")
        plot_curve( solution,solution.solution_constr, p0, pf, mu,  false, 'r', true, params);
    case -2  
        fprintf(2,"Problem didnt converge!\n")
        plot_curve( solution,solution.solution_constr, p0, pf, mu,  false, 'k', true, params);
    case 2 
        fprintf(2,"semidefinite solution (should modify the cost)\n")
        plot_curve( solution,solution.solution_constr, p0, pf, mu,  false, 'r', true, params);

    case 0 
        fprintf(2,"Max number of feval exceeded (10000)\n")
end

%max power corde ista
max_power_l = max(abs(solution.l1d_fine .* solution.Fr_l_fine));
max_power_r = max(abs(solution.l2d_fine .* solution.Fr_r_fine));

fprintf('Fleg:  %f %f %f \n\n',solution.Fleg(1), solution.Fleg(2), solution.Fleg(3))
fprintf('cost:  %f\n\n',solution.cost)
fprintf('final_kin_energy:  %f\n\n',solution.Ekinf)
fprintf('final_error_real:  %f\n\n',solution.final_error_real)
fprintf('final_error_discrete:  %f\n\n', solution.solution_constr.final_error_discrete)
fprintf('max_integration_error:  %f\n\n', solution.final_error_real - solution.solution_constr.final_error_discrete)

P_media = solution.Ekinf / (solution.time_fine(end) - solution.time_fine(1));
fprintf('Potenza media stimata: %f W\n\n', P_media);

%plot max power corde
fprintf('Max power istant (corda dx): %f W\n\n', max_power_r);
fprintf('Max power istant (corda sx): %f W\n\n', max_power_l);

figure;
hold on;
plot(solution.time_fine, abs(solution.l1d_fine .* solution.Fr_l_fine), 'b', 'DisplayName', 'Corda sx');
plot(solution.time_fine, abs(solution.l2d_fine .* solution.Fr_r_fine), 'r', 'DisplayName', 'Corda dx');
hold off;

xlabel('Tempo [s]');
ylabel('Potenza [W]');
title('Potenza istantanea corde');
legend;
grid on;




DEBUG = false;

if (DEBUG)
    eval_constraints(solution.c, solution.num_constr, solution.constr_tolerance)  
    figure
    ylabel('Fr-X')
    plot(solution.time,0*ones(size(solution.Fr_l)),'k'); hold on; grid on;
    plot(solution.time,-Fr_max*ones(size(solution.Fr_l)),'k');
    plot(solution.time,solution.Fr_l,'r');
    plot(solution.time,solution.Fr_r,'b');
    legend({'min','max','Frl','Frr'});
    
    figure
    subplot(3,1,1)
    plot(solution.time, solution.p(1,:),'r') ; hold on;   grid on; 
    plot(solution.solution_constr.time, solution.solution_constr.p(1,:),'ob') ; hold on;    
    ylabel('X')
    
    subplot(3,1,2)
    plot(solution.time, solution.p(2,:),'r') ; hold on;  grid on;  
    plot(solution.solution_constr.time, solution.solution_constr.p(2,:),'ob') ; hold on;    
    ylabel('Y')
    
    subplot(3,1,3)
    plot(solution.time, solution.p(3,:),'r') ; hold on; grid on;   
    plot(solution.solution_constr.time, solution.solution_constr.p(3,:),'ob') ; hold on;
    ylabel('Z')

       

%     figure
%     subplot(3,1,1)
%     plot(solution.time, solution.psi,'r');hold on; grid on;
%     plot(solution_constr.time, solution_constr.psi,'ob');
%     ylabel('psi')
% 
%     subplot(3,1,2)
%     plot(solution.time, solution.l1,'r');hold on; grid on;
%     plot(solution_constr.time, solution_constr.l1,'ob');
%     ylabel('phi')
%     
%     subplot(3,1,3)
%     plot(solution.time, solution.l2,'r'); hold on; grid on;
%     plot(solution_constr.time, solution_constr.l2,'ob');
%     ylabel('l')
%     
%     figure
%     subplot(3,1,1)
%     plot(solution.time, solution.psid,'r');hold on; grid on;
%     plot(solution_constr.time, solution_constr.psid,'ob');
%     ylabel('thetad')
% 
%     subplot(3,1,2)
%     plot(solution.time, solution.l1d,'r');hold on; grid on;
%     plot(solution_constr.time, solution_constr.l1d,'ob');
%     ylabel('phid')
%     
%     subplot(3,1,3)
%     plot(solution.time, solution.l2d,'r'); hold on; grid on;
%     plot(solution_constr.time, solution_constr.l2d,'ob');
%     ylabel('ld')
   
    
end

fprintf('Leg impulse force: %f %f %f\n\n', solution.Fleg);
fprintf('Jump Duration: %f\n\n', solution.Tf);
fprintf('Landing Target: %f %f %f\n\n', solution.achieved_target);

[impulse_work , hoist_work, hoist_work_fine] = computeJumpEnergyConsumption(solution,params);
Energy_consumed = impulse_work+hoist_work_fine;
fprintf('Energy_consumed [J]: %f \n\n', Energy_consumed);

% Calcolo di coppia motore, velocità cavo, e potenza istantanea (lato dx)
torque_dx   = solution.Fr_r_fine * r_spool;                 % [Nm]
velocity_dx = solution.l2d_fine;                            % [m/s]
power_dx    = solution.Fr_r_fine .* solution.l2d_fine;      % [W] 
% se vuoi solo il valore assoluto della potenza: abs(power_dx)

% Grafico della coppia motore di destra
figure
plot(solution.time_fine, torque_dx);
xlabel('Tempo [s]');
ylabel('Coppia motore dx [Nm]');
title('Coppia motore di destra');
grid on;

% Grafico della velocità del cavo di destra
% Calcolo degli rpm a partire dalla velocità in m/s
rpm_dx = (velocity_dx / (2*pi*r_spool)) * 60;

figure
plot(solution.time_fine, rpm_dx);
xlabel('Tempo [s]');
ylabel('Velocità [rpm]');
title('Velocità in rpm (cavo/motore dx)');
grid on;

% Grafico della potenza (lato dx)
figure
plot(solution.time_fine, power_dx);
xlabel('Tempo [s]');
ylabel('Potenza [W]');
title('Potenza motore di destra');
grid on;

% Nome della cartella dove salvare i dati
folder_name = 'dati_motore';

% Crea la cartella se non esiste già
if ~exist(folder_name, 'dir')
    mkdir(folder_name);
end

% Percorso completo del file CSV all'interno della cartella
file_csv = fullfile(folder_name, 'dati_motore_dx.csv');


% Salva i dati includendo il tempo
output_data = [solution.time_fine', torque_dx', rpm_dx', power_dx'];
header = {'Tempo_s', 'Coppia_dx_Nm', 'RPM_dx', 'Potenza_dx_W'};

% Scrittura header
fid = fopen(file_csv, 'w');
fprintf(fid, '%s,%s,%s,%s\n', header{:});
fclose(fid);

% Scrittura dati
writematrix(output_data, file_csv, 'WriteMode', 'append');



figure;
hold on;
plot(solution.time_fine, abs(solution.l1d_fine .* solution.Fr_l_fine), 'b', 'DisplayName', 'Corda sx');
plot(solution.time_fine, abs(solution.l2d_fine .* solution.Fr_r_fine), 'r', 'DisplayName', 'Corda dx');
hold off;

xlabel('Tempo [s]');
ylabel('Potenza [W]');
title('Potenza istantanea corde');
legend;
grid on;

fprintf('---------------------------------------\n')
fprintf('Leg impulse force: %f %f %f\n', solution.Fleg);
fprintf('Jump Duration: %f\n', solution.Tf);
fprintf('Landing Target: %f %f %f\n', solution.achieved_target);
fprintf('---------------------------------------\n')

fprintf('---------------------------------------\n')
[impulse_work , hoist_work, hoist_work_fine] = computeJumpEnergyConsumption(solution,params);
Energy_consumed = impulse_work+hoist_work_fine;
fprintf('Energy_consumed [J]: %f \n\n', Energy_consumed);
fprintf('---------------------------------------\n')

fprintf('---------------------------------------\n')
fprintf('-----------------other value----------------------\n')
%
P_media = solution.Ekinf / (solution.time_fine(end) - solution.time_fine(1));
fprintf('Potenza media stimata: %f W\n\n', P_media);

%plot max power corde
fprintf('Max power istant (corda dx): %f W\n', max_power_r);
fprintf('Max power istant (corda sx): %f W\n', max_power_l);

v_max_l = max(abs(solution.l1d_fine)); % Velocità massima della corda sinistra
v_max_r = max(abs(solution.l2d_fine)); % Velocità massima della corda destra

fprintf('Velocità massima della corda sx: %f m/s\n', v_max_l);
fprintf('Velocità massima della corda dx: %f m/s\n', v_max_r);

a_l = diff(solution.l1d_fine) ./ diff(solution.time_fine);
a_r = diff(solution.l2d_fine) ./ diff(solution.time_fine);

a_max_l = max(abs(a_l)); % Accelerazione massima corda sinistra
a_max_r = max(abs(a_r)); % Accelerazione massima corda destra

fprintf('Accelerazione massima della corda sx: %f m/s^2\n', a_max_l);
fprintf('Accelerazione massima della corda dx: %f m/s^2\n', a_max_r);


figure;
hold on;
plot(solution.time_fine(1:end-1), abs(a_l), 'r', 'DisplayName', 'Acc. corda sx');
plot(solution.time_fine(1:end-1), abs(a_r), 'b', 'DisplayName', 'Acc. corda dx');
hold off;

xlabel('Tempo [s]');
ylabel('Accelerazione [m/s^2]');
title('Accelerazione delle corde');
legend;
grid on;
