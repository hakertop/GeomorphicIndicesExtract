classdef Utils
    methods (Static)
        function elevation = get_elevation(dem, x, y)
            % get_elevation 函数用于从 dem 数据中获取指定 (x, y) 坐标的高程值
            % 输入：
            %   dem：流域的DEM数据 - GRIDobj
            %   x：横坐标 - number
            %   y：纵坐标 - number
            % 输出：
            %   elevation：找到的有效高程值 - number

            % 通过流域多边形边界得到的坐标转换为栅格二维矩阵下标的时候可能存在误差
            % 因此此处在找不到有效值的时候搜索临近像素去获取高程值
            % 具体按照广度优先搜索的方式进行搜索
            [row, col] = dem.coord2sub(x, y);
            if ~isnan(dem.Z(row, col))
                elevation = dem.Z(row, col);
                return;
            end
            direction = [[1, 0]; [-1, 0]; [0, 1]; [0, -1]];
            queue = [row, col];
            visited = false(dem.size);
            visited(row, col) = true;
            while ~isempty(queue)
                [row, col] = queue(1);
                queue(1) = [];
                for i = 1 : 4
                    next_row = row + direction(i, 1);
                    next_col = col + direction(i, 2);
                    if next_row < 1 || next_row > dem.size(1) || ...
                        next_col < 1 || next_col > dem.size(2) || ...
                        visited(next_row, next_col)
                        continue;
                    end
                    if ~isnan(dem.Z(next_row, next_col))
                        elevation = dem.Z(next_row, next_col);
                        return;
                    end
                    queue = [queue; [next_row, next_col]];
                    visited(next_row, next_col) = true;
                end
            end
            elevation = NaN;
        end

        function area = calculate_polygon_area(polygon_x, polygon_y)
            % calculate_polygon_area 函数用于计算由 polygon_x 和 polygon_y 表示的多边形的面积
            % 输入：
            %   polygon_x：多边形顶点的横坐标数组
            %   polygon_y：多边形顶点的纵坐标数组
            % 输出：
            %   area：多边形的面积

            % 使用叉积公式计算多边形面积
            x = polygon_x(:);
            y = polygon_y(:);

            % 计算相邻顶点的叉积，得到叉积数组
            cross = x(1:end-2).* y(2:end-1) - x(2:end-1).* y(1:end-2); 
            cross = cross(~isnan(cross)); % 移除 NaN 值

            % 计算叉积绝对值的和并乘以 0.5 得到面积
            area = 0.5 * abs(sum(cross)); 
        end

        function distance = get_distance(x1, y1, x2, y2)
            % get_distance 函数用于计算两点 (x1, y1) 和 (x2, y2) 之间的欧几里得距离
            % 输入：
            %   x1：第一个点的横坐标
            %   y1：第一个点的纵坐标
            %   x2：第二个点的横坐标
            %   y2：第二个点的纵坐标
            % 输出：
            %   distance：两点之间的距离

            % 计算两点之间的欧几里得距离
            distance = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2); 
        end

        function export_selected_basins(dem_file_path, output_workspace)
            %% 流域分析，选取所需的流域导出为 TIF
            %
            % 输入参数：
            %   dem_file_path - 研究区 DEM 路径 
            %   output_workspace - 输出文件夹
            %
            % 输出数据：output_workspace 中生成
            %   basins_id_list - 流域id列表 
            %   basins\basin_(id).tif - 流域范围DEM，其中id为其编号
        
            % 检查输入文件和输出文件夹
            if ~isfile(dem_file_path)
                error('DEM 文件路径无效：%s', dem_file_path);
            end
            if ~isfolder(output_workspace)
                mkdir(output_workspace);
            end
            output_workspace = fullfile(output_workspace, "basins\");
            if ~exist(output_workspace, "dir")
                mkdir(output_workspace);
            end
            
            % 加载 DEM 并进行填洼、高斯滤波
            dem = fillsinks(GRIDobj(dem_file_path));
            dem.Z = imgaussfilt(dem.Z, 2);
            
            % 流向分析
            flow_direction = FLOWobj(dem);
            
            % 流域分析
            basins = drainagebasins(flow_direction);
            [~, L_x, L_y] = GRIDobj2polygon(basins);
            
            % 可视化
            figure;
            imageschs(dem, basins, 'colormap', lines);
            hold on;
            plot(L_x, L_y, 'Color', 'w', 'LineWidth', 2);
            hold off;
            title('流域分区（单击左键选择感兴趣的流域）');
            
            % 用户交互选择流域
            selected_basins = ginput();
            % 将地理坐标转换为矩阵索引
            [row, col] = dem.coord2sub(selected_basins(:, 1), selected_basins(:, 2));
            % 根据矩阵索引提取流域 ID
            selected_ids = unique(basins.Z(sub2ind(size(basins.Z), row, col)));
            selected_ids(selected_ids == 0) = []; % 排除背景值
            
            % id列表存为txt
            fid = fopen(strcat(output_workspace, "../basins_id_list.txt"), "w+");
        
            % 导出选定流域为 TIF
            for id = selected_ids'
                fprintf(fid, "%d\n", id);
                % 生成该流域的文件夹
                basin_output_file = strcat(output_workspace, "\basin_", num2str(id), "\");
                if ~exist(basin_output_file, "dir")
                    mkdir(basin_output_file);
                end
        
                mask = basins == id;
                basin_elevation = dem;
                basin_elevation.Z(~mask.Z) = NaN; % 非流域区域设置为 NaN
                bound = Utils.extract_valid_bound(basin_elevation);
                basin_elevation = crop(basin_elevation, [bound(1), bound(3)], [bound(2), bound(4)]);
                output_file = fullfile(basin_output_file, sprintf('basin_%d.tif', id));
                basin_elevation.GRIDobj2geotiff(output_file);
                 % 展示导出的DEM
                 
                 figure;
                 imageschs(basin_elevation);
                 title(strcat("流域 ", num2str(id), " DEM"));
                fprintf('流域 %d 导出到 %s\n', id, output_file);
            end
            
            fclose(fid);
            
            disp('流域导出完成！');
        end
        
        function rectangle = extract_valid_bound(gridObj)
            %% 提取TopoToolBox GRIDobj对象的有效范围（忽略四边NaN值）
            %
            % 输入参数：
            %   - gridObj: GRIDobj 对象
            %
            % 输出参数：
            %   - geoBounds: 包含有效范围的地理坐标，格式为 [minX, minY, maxX, maxY]
            %
            % 主要是由于TopoToolBox生成的GRIDobj周边包含了大量的NaN无法去除，因此使用此函数获取有效范围
            % 得到有效范围后可以用来限制可视化时的范围
        
            % 检查输入类型
            if ~isa(gridObj, 'GRIDobj')
                error('输入必须是GRIDobj对象');
            end
        
            % 提取有效区域的逻辑索引
            validMask = ~isnan(gridObj.Z);
        
            % 如果整个 GRIDobj 都是 NaN，直接返回空
            if all(~validMask, 'all')
                warning('GRIDobj 对象中没有有效数据');
                rectangle = [];
                return;
            end
        
            % 找到包含有效数据的行和列范围
            rowIndices = find(any(validMask, 2));
            colIndices = find(any(validMask, 1));
        
            minRow = rowIndices(1);
            maxRow = rowIndices(end);
            minCol = colIndices(1);
            maxCol = colIndices(end);
        
            % 转换为地理坐标
            [minX, minY] = gridObj.sub2coord(maxRow, minCol);
            [maxX, maxY] = gridObj.sub2coord(minRow, maxCol);
        
            % 返回地理范围
            rectangle = [minX, minY, maxX, maxY];
        end
    end
end