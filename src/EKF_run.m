function varargout = EKF_run()
    %% Load data
    addpath([cd, '/../data'])
    data = load('data_2013-01-10.mat');
    
    %% Initialization
    % Use first GPS measurement as initial position 
    [x, y, z] = latlngalt2xyz(data.gps_cg.latitude(1), ...
                              data.gps_cg.longitude(1), ...
                              data.gps_cg.altitude(1));
    gpsFirstTimestamp = data.gps_cg.timestamp(1);
    imuFirstIndex = find(data.imu.timestamp > gpsFirstTimestamp, 1);
    
    % Use groundtruth orientation to construct initial rotation matrix
    [~, groundtruthFirstIndex] = min(abs(data.ground_truth.timestamp - gpsFirstTimestamp));
    eulerInitial = [data.ground_truth.roll(groundtruthFirstIndex) ...
                    data.ground_truth.pitch(groundtruthFirstIndex) ...
                    data.ground_truth.heading(groundtruthFirstIndex)];
                
    % 'XYZ' (roll, pitch, yaw), body-fixed (intrinsic) axis rotation sequence.     
    init.X = [eulerInitial'; zeros(3,1); [x;y;z]];
    init.P = eye(9);

    sys.H = [0*zeros(2,3), 0*zeros(2,3), [1 0 0;0 1 0]];
    sys.Q = blkdiag(1e-2*eye(3), 1e-2*eye(3), 1e-2*eye(3));  %% reduce the process noise
    sys.R = 10 * eye(2);   %% increase the measurement noise to trust less on the measurements


    filter = EKF(sys, init);
    
    %% Extended Kalman filter
    gpsIndex = 2;
    % lastValidAltitude = data.gps_cg.altitude(1);
    filteredData = zeros(length(data.gps_cg.timestamp)-1, 13);
    filteredDataStatistics = zeros(length(data.gps_cg.timestamp)-1, 11);
    
    for imuIndex = imuFirstIndex: length(data.imu.accel_x)-1
        disp(imuIndex)
        acceleration = [data.imu.accel_x(imuIndex);
                        data.imu.accel_y(imuIndex);
                        data.imu.accel_z(imuIndex)];
        angularRate = [data.imu.gyro_x(imuIndex);
                       data.imu.gyro_y(imuIndex);
                       data.imu.gyro_z(imuIndex)];
        imuTimestamp = data.imu.timestamp(imuIndex);
        nextImuTimeStamp = data.imu.timestamp(imuIndex+1);
        dt = nextImuTimeStamp - imuTimestamp;
        
        % If there is GPS data coming between two IMU timestamps
        if gpsIndex <= length(data.gps_cg.timestamp) && nextImuTimeStamp > data.gps_cg.timestamp(gpsIndex)
            gpsTimestamp = data.gps_cg.timestamp(gpsIndex);
            % Find the index of the closest timestamp in groundtruth data
            [~, groundtruthIndex] = min(abs(data.ground_truth.timestamp - gpsTimestamp));
            groundtruth = [data.ground_truth.roll(groundtruthIndex);
                           data.ground_truth.pitch(groundtruthIndex);
                           data.ground_truth.heading(groundtruthIndex);
                           data.ground_truth.x(groundtruthIndex);
                           data.ground_truth.y(groundtruthIndex);
                           data.ground_truth.z(groundtruthIndex)];
            
            % If in case gps_cg.altitude is NaN
    %         if isnan(data.gps_cg.altitude(gpsIndex))
    %             altitude = lastValidAltitude;
    %         else
    %             altitude = data.gps_cg.altitude(gpsIndex);
    %             lastValidAltitude = altitude;
    %         end
            [x, y, z] = latlngalt2xyz(data.gps_cg.latitude(gpsIndex), ...
                                      data.gps_cg.longitude(gpsIndex), ...
                                      0);
            Y = [x;y];
            filter.update(Y);
            gpsIndex = gpsIndex + 1;
            
            % gpsTimestamp, yaw, pitch, roll, x, y, z
            filteredData(gpsIndex - 2, :) = [gpsTimestamp filter.X(1:3)' filter.X(7:9)' groundtruth'];
            filteredDataStatistics(gpsIndex - 2, :) = mahalanobis(filter, groundtruth, 2);     
        end
        
        filter.prediction(angularRate, acceleration, dt);
    end
    
    %% Output data
    if nargout >= 1
        varargout{1} = filteredData;
    end
    
    if nargout >= 2
        varargout{2} = filteredDataStatistics;
    end